vim9script

g:ezpack_home = expand(get(g:, 'ezpack_home', $"{has('win32') ? '~/vimfiles' : '~/.vim'}/pack/ezpack"))

var plugins = []

def GetPluginName(url: string): string
  return url->matchlist('.*/\([^/]*\)$')[1]->substitute('\.git$', '', '')
enddef

def GetPath(url: string, opt: string): string
  return $'{g:ezpack_home}/{opt}/{GetPluginName(url)}'
enddef

def MkParent(path: string)
  system($'mkdir -p {path->substitute('/[^/]*$', '', '')}')
enddef

def GitPull(): list<any>
  var cloned = []
  const l = plugins->len()
  var i = 0
  for p in plugins
    i += 1
    const path = expand(GetPath(p.url, !p.trigger ? 'start' : 'opt'))
    const extra = expand(GetPath(p.url, !!p.trigger ? 'start' : 'opt'))
    if isdirectory(extra) && !isdirectory(path)
      rename(extra, path)
    endif
    var label = 'pull'
    var gitcmd = $'git pull {path}'
    if !isdirectory(path)
      cloned += [path]
      MkParent(path)
      label = 'clone'
      gitcmd = $'git clone {p.url} {path}'
    endif
    echo $'Ezpack: ({i}/{l}) {label} {p.name}'
    const result = system(gitcmd)
    if v:shell_error !=# 0 && v:shell_error !=# 128
      echoe gitcmd
      echoe result
    endif
    redraw!
  endfor
  return cloned
enddef

# TODO: Is this unnecessary?
def ExecuteCloned(cloned: list<string>)
  &rtp = $'{cloned->join(',')},{&rtp}'
  for c in cloned
    for f in globpath($'{c}/plugins', '*.vim')
      execute 'source' f
    endfor
  endfor
enddef

def CreateAutocmd(): string
  var lines = ['vim9script', 'augroup ezpack', 'au!']
  for p in plugins
    if !p.trigger
      continue
    endif
    lines += [$"au ezpack {p.trigger} packadd {GetPluginName(p.url)}"]
  endfor
  lines += ['augroup END']
  const path = expand($'{g:ezpack_home}/start/_/plugin/_.vim')
  MkParent(path)
  writefile(lines, path)
  return path
enddef

# -----------------------
# Interface

export def Init()
  plugins = []
enddef

export def Ezpack(...fargs: list<any>)
  plugins += [{
    name: fargs[0],
    url: fargs[0] =~# '\.git$' ? fargs[0] : $'https://github.com/{fargs[0]}.git',
    trigger: fargs[1 : ]->join(' '),
  }]
enddef

export def Install()
  doautocmd User EzpackInstallPre
  const cloned = GitPull()
  const autoCmdPath = CreateAutocmd()
  ExecuteCloned(cloned)
  execute 'source' autoCmdPath
  echo 'Ezpack: COMPLETED.'
enddef

