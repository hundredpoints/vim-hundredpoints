" Check Vim version
if v:version < 700
  echoerr "This plugin requires vim >= 7."
  finish
endif


let s:true = 1
let s:false = 0

" Only load plugin once
if exists("g:loaded_hundredpoints")
  finish
endif
let g:loaded_hundredpoints = s:true


let s:save_cpo = &cpo " save user coptions
set cpo&vim " reset them to defaults


" Backup wildignore before clearing it to prevent conflicts with expand()
let s:wildignore = &wildignore
if s:wildignore != ""
  set wildignore=""
endif
function! s:GetConfigSetting(section, key, ...)

  if exists(a:0)
    let s:default = a:0
  else
    let s:default = get(s:default_config, a:key)
  endif

  if has_key(s:config, a:section)
    return get(s:config[a:section], a:key, s:default)
  else
    return s:default
  endif
endfunction

function! s:SetConfigSetting(section, key, value)
  let settings = IniParser#Read(s:config_file)
  let section_settings = get(settings, a:section, {})

  let new_settings = {}
  let new_settings[a:key] = a:value

  let new_section_settings = extend(section_settings, new_settings)

  let settings[a:section] = new_section_settings

  call IniParser#Write(settings, s:config_file)
  let s:config = settings
  let s:default_config = get(s:config, "default", {})
  return new_settings
endfunction

let s:debug = get(g:, 'hundredpoints_debug', s:false)
let s:debug_mode_already_setup = s:false

let s:profile = get(g:, 'hundredpoints_profile', "vim")

let s:logged_in = s:false
let s:already_verified_token = s:false
let s:already_shown_no_access_token_message = s:false
let s:home = expand("$HOME")
let s:default_settings = "default"
let s:config_file = s:home . '/.hundredpoints'
let s:config_file_already_setup = s:false
let s:config = IniParser#Read(s:config_file)
let s:default_config = get(s:config, "default", {})
let s:default_configs = ['[default]', 'origin=https://hundredpoints.io', 'api=/api/graphql']

let s:plugin_dir = resolve(expand('<sfile>:p') . "/../")
let s:cli_path = s:GetConfigSetting(s:default_settings, "cli_path", s:plugin_dir . "/node_modules/.bin/hundredpoints")

let s:has_async = has('patch-7.4-2344') && exists('*job_start')
let s:nvim_async = exists('*jobstart')

" Heartbeat config
let s:last_heartbeat = {'last_activity_at': 0, 'last_heartbeat_at': 0, 'file': ''}
let s:data_file = s:home . '/.hundredpoints.data'
let s:local_cache_expire = 10  " seconds between reading s:data_file
let s:heartbeats_buffer = []
let s:send_buffer_seconds = 30  " seconds between sending buffered heartbeats
let s:buffering_heartbeats_enabled = s:has_async || s:nvim_async || !s:IsWindows()
let s:last_sent = localtime()
if !exists("g:hundredpoints_HeartbeatFrequency")
  let g:hundredpoints_HeartbeatFrequency = 2 " Set default heartbeat frequency in minutes
endif

" Helper functions {{{
function! s:NumberToString(number)
  return substitute(printf('%d', a:number), ',', '.', '')
endfunction

function! s:IsWindows()
  if has('win32') || has('win64')
    return s:true
  endif
  return s:false
endfunction
" }}}


" Binary {{{
function! s:UpdatePlugin()
  silent execute "!cd " . s:plugin_dir . "../; npm ci;"
call s:ExecuteCommand("-v", function('s:EchoMsg'))
endfunction

function! s:ExecuteCommand(command, callback)
  let full_command = s:cli_path . ' --no-interactive -j -p=' . s:profile . ' ' . a:command

  if s:has_async
    let job = job_start(full_command, {
          \ 'stoponexit': '',
          \ 'callback': {channel, output -> a:callback(output)}})
  elseif s:nvim_async
    let s:nvim_async_output = ['']
    let s:nvim_async_callback = a:callback
    let job = jobstart(full_command, {
        \ 'detach': 1,
        \ 'on_stdout': function('s:NeovimAsyncOutputHandler'),
        \ 'on_stderr': function('s:NeovimAsyncOutputHandler'),
        \ 'on_exit': function('s:NeovimAsyncExitHandler')})
  else
    call a:callback(system(full_command))
  endif
endfunction

function! s:NeovimAsyncOutputHandler(job_id, output, event)
  let s:nvim_async_output[-1] .= a:output[0]
  call extend(s:nvim_async_output, a:output[1:])
endfunction

function! s:NeovimAsyncExitHandler(job_id, output, event)
  call s:nvim_async_callback(join(s:nvim_async_output, ""))
endfunction
" }}}

" Heartbeats {{{
function! s:GetLastHeartbeat()
  if !s:last_heartbeat.last_activity_at || localtime() - s:last_heartbeat.last_activity_at > s:local_cache_expire
    if !filereadable(s:data_file)
      return {'last_activity_at': 0, 'last_heartbeat_at': 0, 'file': ''}
    endif
    let last = readfile(s:data_file, '', 2)
    if len(last) == 3
      let s:last_heartbeat.last_heartbeat_at = last[0]
      let s:last_heartbeat.file = last[1]
    endif
  endif
  return s:last_heartbeat
endfunction


function! s:EnoughTimePassed(now, last)
  let prev = a:last.last_heartbeat_at
  if a:now - prev > g:hundredpoints_HeartbeatFrequency * 60
    return s:true
  endif
  return s:false
endfunction

function! s:SetLastHeartbeatInMemory(last_activity_at, last_heartbeat_at, file)
  let s:last_heartbeat = {'last_activity_at': a:last_activity_at, 'last_heartbeat_at': a:last_heartbeat_at, 'file': a:file}
endfunction

function! s:SetLastHeartbeat(last_activity_at, last_heartbeat_at, file)
  call s:SetLastHeartbeatInMemory(a:last_activity_at, a:last_heartbeat_at, a:file)
  call writefile([s:NumberToString(a:last_activity_at), a:file], s:data_file)
endfunction

function! s:AppendHeartbeat(file, now, is_write, last)
  let file = a:file
  if file == ''
    let file = a:last.file
  endif

  if file == ''
    return
  endif

  let heartbeat = {}
  let heartbeat.url = 'file://localhost' . file
  let heartbeat.startDateTime = localtime() * 1000 " The CLI uses millisecond Epoch
  let heartbeat.isWrite = a:is_write
  if !empty(&syntax)
    let heartbeat.language = &syntax
  else
    if !empty(&filetype)
      let heartbeat.language = &filetype
    endif
  endif

  let s:heartbeats_buffer = s:heartbeats_buffer + [heartbeat]
  call s:SetLastHeartbeat(a:now, a:now, file)

  if !s:buffering_heartbeats_enabled
    call s:SendHeartbeats()
    " Clear the buffer so we don't double send
    let s:heartbeats_buffer = []
  endif
endfunction

function! s:HandleActivity(is_write)
  if !s:logged_in
    return
  endif

  let file = expand("%:p")
  if !empty(file) && file !~ "-MiniBufExplorer-" && file !~ "--NO NAME--" && file !~ "^term:"
    let last = s:GetLastHeartbeat()
    let now = localtime()

    " Create a heartbeat when saving a file, when the current file
    " changes, and when still editing the same file but enough time
    " has passed since the last heartbeat.
    if a:is_write || s:EnoughTimePassed(now, last) || file != last.file
      call s:AppendHeartbeat(file, now, a:is_write, last)
    else
      if now - s:last_heartbeat.last_activity_at > s:local_cache_expire
        call s:SetLastHeartbeatInMemory(now, last.last_heartbeat_at, last.file)
      endif
    endif

    " Only send buffered heartbeats every s:send_buffer_seconds
    if now - s:last_sent > s:send_buffer_seconds && len(s:heartbeats_buffer) > 0
      call s:SendHeartbeats()
    endif
  endif
endfunction



function! s:SendHeartbeats()
  let start_time = localtime()

  if len(s:heartbeats_buffer) == 0
    let s:last_sent = start_time
    return
  endif

  let json = json_encode(s:heartbeats_buffer)
  let s:heartbeats_buffer = []

  let s:last_sent = localtime()

  call s:DebugMsg("sending activity")

  call s:ExecuteCommand("activity --git '" . json . "'", function('s:SendHeartbeatsCleanup'))
endfunction

function! s:SendHeartbeatsCleanup(output)
  call s:DebugMsg(a:output)
  " need to repaint in case a key was pressed while sending
  if !s:has_async && !s:nvim_async && s:redraw_setting != 'disabled'
    if s:redraw_setting == 'auto'
      if s:last_sent - start_time > 0
        redraw!
      endif
    else
      redraw!
    endif
  endif
endfunction
" }}}

function! s:PromptForApiKey(output)
  call input('[Hundredpoints] A browser has been opened to generate an access token, press any key to continue')

  let token = inputsecret("[Hundredpoints] Enter your access token:")

  if strlen(token) == 0
    call s:EchoMsg("No key entered")
    return
  endif

  call s:ExecuteCommand("profile set-token " . token, { response -> s:VerifyLogin(token, response) })

endfunction

" Setup {{{
function! s:InitAndHandleActivity(is_write)
  if !filereadable(s:cli_path)
    return
  endif

  if !s:already_verified_token && !s:logged_in
    let s:already_verified_token = s:true
    call s:ExecuteCommand("me", function('s:SilentVerifyLogin'))
  endif

  call s:SetupDebugMode()
  call s:SetupConfigFile()

  if s:logged_in
    call s:HandleActivity(a:is_write)
  endif
endfunction

function! s:SilentVerifyLogin(cli_response)
  silent call s:VerifyLogin(a:cli_response)
endfunction

function! s:VerifyLogin(cli_response)
  let response = s:HandleCliResponse(a:cli_response)

  if has_key(response, "error")
    return
  endif

  echo response

  if !has_key(response, "installedBy")
    return
  endif

  call s:EchoMsg(json_encode(response))

  let s:logged_in = s:true
endfunction

function! s:SetupDebugMode()
  if !s:debug_mode_already_setup
    if s:GetConfigSetting('vim', 'debug') == 'true'
      let s:debug = s:true
      call s:DebugMsg("debug is enabled")
    else
      let s:debug = s:false
    endif
    let s:debug_mode_already_setup = s:true
  endif
endfunction

function! s:SetupConfigFile()
  if !s:config_file_already_setup
    if !filereadable(s:config_file)
      call writefile(s:default_configs, s:config_file)
    endif
  endif
endfunction
" }}}


function! s:DebugMsg(output)
  if s:debug == s:true
    echomsg "[Hundredpoints] [debug] " . a:output
  endif
endfunction

function! s:EchoMsg(output)
  echomsg "[Hundredpoints] " . a:output
endfunction

function! s:EchoErrorMsg(output)
  echomsg "[Hundredpoints] [error] " . a:output
endfunction


function s:HandleCliResponse(json_response)
  let response = json_decode(a:json_response)

  if has_key(response, "error")
    try
      let error = response.error
      if has_key(error, "description")
        call s:EchoErrorMsg(error.description)
      elseif has_key(error, "message")
        call s:EchoErrorMsg(error.message)
      else
        call s:EchoErrorMsg(error)
      endif
    catch
      call s:EchoErrorMsg(v:exception)
    endtry
  endif

  return response
endfunction

function s:HundredpointsStatus()
  call s:EchoMsg("Logged In:" . s:logged_in . " Debug:" . s:debug)
endfunction

function s:HundredpointsReset()
let s:debug_mode_already_setup = s:false
let s:debug = s:false

let s:config_file_already_setup = s:false

let s:already_verified_token = s:false
let s:already_shown_no_access_token_message = s:false
let s:logged_in = s:false
endfunction


function s:EchoCliResponse(cli_response)
  let response = s:HandleCliResponse(a:cli_response)

  if has_key(response, "error")
    return
  endif

  call s:EchoMsg(json_encode(response))
endfunction

" Autocommand Events {{{
augroup Hundredpoints
  autocmd BufEnter,VimEnter * call s:InitAndHandleActivity(s:false)
  autocmd CursorMoved,CursorMovedI * call s:HandleActivity(s:false)
  autocmd BufWritePost * call s:HandleActivity(s:true)
  if exists('##QuitPre')
    autocmd QuitPre * call s:SendHeartbeats()
  endif
augroup END
" }}}

" Plugin Commands {{{
command! -nargs=0 HundredpointsSetup call s:ExecuteCommand("integration install vim", function('s:PromptForApiKey'))
command! -nargs=0 HundredpointsLogin call s:ExecuteCommand("me", function('s:VerifyLogin'))
command! -nargs=0 HundredpointsLogout call s:ExecuteCommand("profile remove", function('s:EchoCliResponse'))
command! -nargs=0 HundredpointsMe call s:ExecuteCommand("me", function('s:VerifyLogin'))
command! -nargs=0 HundredpointsReset call s:HundredpointsReset()
command! -nargs=0 HundredpointsStatus call s:HundredpointsStatus()
command! -nargs=0 HundredpointsUpdate call s:UpdatePlugin()
command! -nargs=0 HundredpointsVersion call s:ExecuteCommand("-v", function('s:EchoMsg'))
" }}}

" Restore wildignore option
if s:wildignore != ""
    let &wildignore=s:wildignore
endif

" Restore cpoptions
let &cpo = s:save_cpo
