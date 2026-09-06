set completeopt=menuone,noselect
filetype on

if !has('job') || !has('channel') || !executable('clangd')
  finish
endif

let s:client = {}
let s:pending = {}
let s:uri_buf = {}

function! s:Uri(path) abort
  let p = substitute(fnamemodify(a:path, ':p'), '\\', '/', 'g')
  let p = substitute(p, '%', '%25', 'g')
  let p = substitute(p, ' ', '%20', 'g')
  let p = substitute(p, '#', '%23', 'g')
  return 'file://' . (p =~# '^\a:/' ? '/' : '') . p
endfunction

function! s:CompileDir(file) abort
  let dir = fnamemodify(a:file, ':p:h')
  while 1
    if filereadable(dir . '/compile_commands.json')
      return dir
    endif
    let db = glob(dir . '/*/compile_commands.json', 0, 1)
    if !empty(db)
      return fnamemodify(db[0], ':h')
    endif
    let parent = fnamemodify(dir, ':h')
    if parent ==# dir | break | endif
    let dir = parent
  endwhile
  return ''
endfunction

function! s:Text(buf) abort
  return join(getbufline(a:buf, 1, '$'), "\n") . "\n"
endfunction

function! s:Notify(method, params) abort
  if !empty(s:client)
    call ch_sendexpr(s:client.channel, {'method': a:method, 'params': a:params})
  endif
endfunction

function! s:Open(buf) abort
  if empty(s:client) || !s:client.ready || !bufexists(a:buf)
    return
  endif
  if getbufvar(a:buf, 'clangd_key', '') ==# s:client.key
    return
  endif

  let uri = s:Uri(bufname(a:buf))
  let s:uri_buf[uri] = a:buf
  call setbufvar(a:buf, 'clangd_key', s:client.key)
  call s:Notify('textDocument/didOpen', {'textDocument': {
        \ 'uri': uri,
        \ 'languageId': getbufvar(a:buf, '&filetype'),
        \ 'version': getbufvar(a:buf, 'changedtick'),
        \ 'text': s:Text(a:buf),
        \ }})
endfunction

function! s:Initialized(key, channel, msg) abort
  if empty(s:client) || s:client.key !=# a:key || has_key(a:msg, 'error')
    return
  endif
  let s:client.ready = 1
  call s:Notify('initialized', {})
  for buf in keys(s:pending)
    call s:Open(str2nr(buf))
  endfor
  let s:pending = {}
endfunction

function! s:Diagnostics(params) abort
  if !exists('*prop_add')
    return
  endif
  let buf = get(s:uri_buf, get(a:params, 'uri', ''), -1)
  if buf < 0 || !bufexists(buf)
    return
  endif

  silent! call prop_remove({'types': ['ClangdError', 'ClangdWarn', 'ClangdInfo'], 'bufnr': buf, 'all': 1})
  let seen = {}
  for d in get(a:params, 'diagnostics', [])
    let lnum = get(get(get(d, 'range', {}), 'start', {}), 'line', 0) + 1
    if has_key(seen, string(lnum)) | continue | endif
    let seen[string(lnum)] = 1
    let severity = get(d, 'severity', 3)
    let type = severity == 1 ? 'ClangdError' : severity == 2 ? 'ClangdWarn' : 'ClangdInfo'
    let text = substitute(get(d, 'message', ''), '[\r\n].*$', '', '')
    silent! call prop_add(lnum, 0, {'bufnr': buf, 'type': type, 'text': '  ' . text, 'text_align': 'after'})
  endfor
endfunction

function! s:Message(channel, msg) abort
  if get(a:msg, 'method', '') ==# 'textDocument/publishDiagnostics'
    call s:Diagnostics(get(a:msg, 'params', {}))
  elseif has_key(a:msg, 'method') && has_key(a:msg, 'id')
    call ch_sendexpr(a:channel, {'id': a:msg.id, 'result': v:null})
  endif
endfunction

function! s:Attach(buf) abort
  if index(['c', 'cpp'], getbufvar(a:buf, '&filetype')) < 0 || empty(bufname(a:buf))
    return
  endif

  let db = s:CompileDir(bufname(a:buf))
  let key = empty(db) ? fnamemodify(bufname(a:buf), ':p:h') : db
  let s:pending[string(a:buf)] = 1

  if !empty(s:client) && s:client.key ==# key
    call s:Open(a:buf)
    return
  endif

  if !empty(s:client)
    silent! call job_stop(s:client.job)
  endif

  let cmd = ['clangd', '--header-insertion=never']
  if !empty(db)
    call add(cmd, '--compile-commands-dir=' . db)
  endif

  try
    let job = job_start(cmd, {
          \ 'in_mode': 'lsp',
          \ 'out_mode': 'lsp',
          \ 'err_io': 'null',
          \ 'out_cb': function('<SID>Message'),
          \ })
  catch
    let s:client = {}
    return
  endtry
  if job_status(job) ==# 'fail'
    let s:client = {}
    return
  endif

  let s:client = {'job': job, 'channel': job_getchannel(job), 'key': key, 'ready': 0}
  let root = fnamemodify(bufname(a:buf), ':p:h')
  call ch_sendexpr(s:client.channel, {
        \ 'method': 'initialize',
        \ 'params': {
        \   'processId': exists('*getpid') ? getpid() : v:null,
        \   'rootPath': root,
        \   'rootUri': s:Uri(root),
        \   'capabilities': {
        \     'offsetEncoding': ['utf-8'],
        \     'general': {'positionEncodings': ['utf-8']},
        \     'textDocument': {'completion': {'completionItem': {'snippetSupport': v:false}}},
        \   },
        \ }}, {'callback': function('<SID>Initialized', [key])})
endfunction

function! s:Completion(buf, tick, cursor_col, channel, msg) abort
  if bufnr('%') != a:buf || mode() !~# '^i' || b:changedtick != a:tick || col('.') != a:cursor_col
    return
  endif
  let result = get(a:msg, 'result', [])
  let items = type(result) == v:t_dict ? get(result, 'items', []) : result
  if type(items) != v:t_list || empty(items) | return | endif

  let base = matchstr(strpart(getline('.'), 0, col('.') - 1), '\k*$')
  let matches = []
  for item in items
    let word = get(item, 'insertText', get(item, 'label', ''))
    if has_key(item, 'textEdit')
      let word = get(item.textEdit, 'newText', word)
    endif
    if !empty(word)
      call add(matches, {'word': word, 'abbr': get(item, 'label', word), 'menu': get(item, 'detail', ''), 'dup': 1})
    endif
  endfor
  if !empty(matches)
    call complete(max([1, col('.') - strlen(base)]), matches)
  endif
endfunction

function! s:Changed(buf) abort
  call s:Attach(a:buf)
  if empty(s:client) || !s:client.ready || getbufvar(a:buf, 'clangd_key', '') !=# s:client.key
    return
  endif

  let tick = getbufvar(a:buf, 'changedtick')
  call s:Notify('textDocument/didChange', {
        \ 'textDocument': {'uri': s:Uri(bufname(a:buf)), 'version': tick},
        \ 'contentChanges': [{'text': s:Text(a:buf)}],
        \ })

  if mode() !~# '^i' | return | endif
  let before = strpart(getline('.'), 0, col('.') - 1)
  if empty(before) || before !~# '[[:alnum:]_\.:>]$' | return | endif

  let cursor_col = col('.')
  call ch_sendexpr(s:client.channel, {
        \ 'method': 'textDocument/completion',
        \ 'params': {
        \   'textDocument': {'uri': s:Uri(bufname(a:buf))},
        \   'position': {'line': line('.') - 1, 'character': cursor_col - 1},
        \ }}, {'callback': function('<SID>Completion', [a:buf, tick, cursor_col])})
endfunction

if exists('*prop_type_add')
  silent! call prop_type_add('ClangdError', {'highlight': 'ErrorMsg'})
  silent! call prop_type_add('ClangdWarn', {'highlight': 'WarningMsg'})
  silent! call prop_type_add('ClangdInfo', {'highlight': 'Comment'})
endif

augroup minimal_clangd
  autocmd!
  autocmd FileType c,cpp call <SID>Attach(bufnr('%'))
  autocmd BufEnter * if &l:filetype ==# 'c' || &l:filetype ==# 'cpp' | call <SID>Attach(bufnr('%')) | endif
  autocmd TextChanged,TextChangedI * if &l:filetype ==# 'c' || &l:filetype ==# 'cpp' | call <SID>Changed(bufnr('%')) | endif
augroup END
