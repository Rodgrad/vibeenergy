"""Run inside the Debian build container after installing runtime dependencies."""
from pathlib import Path
import os,re,shutil,subprocess
src=Path('/src'); stage=Path('/out/VibeEnergy.AppDir'); build=Path('/tmp/vibeenergy-build')
subprocess.run(['cmake','-S',str(src),'-B',str(build),'-DCMAKE_BUILD_TYPE=Release','-DBUILD_TESTING=OFF'],check=True)
subprocess.run(['cmake','--build',str(build),'-j2'],check=True)
if stage.exists():shutil.rmtree(stage)
lib=stage/'usr/lib/x86_64-linux-gnu';lib.mkdir(parents=True)
bin_dir=stage/'usr/bin';bin_dir.mkdir()
shutil.copy2(build/'energytlk-splash',bin_dir/'energytlk-splash')
shutil.copy2(build/'energytlk-instance',bin_dir/'energytlk-instance')
for name in ('plasmawindowed','python3'):
 shutil.copy2(Path('/usr/bin')/name,bin_dir/name)
qt=Path('/usr/lib/x86_64-linux-gnu/qt6')
for name in ('qml','plugins'):
 shutil.copytree(qt/name,lib/'qt6'/name,ignore=shutil.ignore_patterns('*.debug'))
stdlib=next(p for p in Path('/usr/lib').glob('python3.*') if (p/'os.py').exists())
shutil.copytree(stdlib,stage/'usr/lib'/stdlib.name,ignore=shutil.ignore_patterns('__pycache__','test','tests','idlelib','tkinter','ensurepip'))
# Linking the interface library alone does not install the Wayland shell plugin.
layer_shell=lib/'qt6/plugins/wayland-shell-integration/liblayer-shell.so'
if not layer_shell.is_file():
 raise RuntimeError('Missing layer-shell-qt runtime plugin required for splash placement')
app=stage/'app';app.mkdir()
shutil.copytree(src/'energytlk',app/'energytlk',ignore=shutil.ignore_patterns('__pycache__'))
shutil.copy2(src/'packaging/appimage/prepare.py',app/'prepare.py')
package=stage/'usr/share/plasma/plasmoids/org.energytlk.monitor'
shutil.copytree(src/'plasmoid',package,ignore=shutil.ignore_patterns('__pycache__'))
shutil.copytree(build/'EnergyLocal',package/'contents/ui/EnergyLocal',dirs_exist_ok=True)
shutil.copy2(build/'libenergytlk-window-alpha.so',lib/'libenergytlk-window-alpha.so')
for name in ('plasma','kf6','color-schemes'):
 path=Path('/usr/share')/name
 if path.exists():shutil.copytree(path,stage/'usr/share'/name,dirs_exist_ok=True)
# Bundle a small font set and compatible fontconfig rules instead of parsing host-version rules.
fonts=Path('/usr/share/fonts/truetype/dejavu')
if fonts.exists():shutil.copytree(fonts,stage/'usr/share/fonts/truetype/dejavu')
noto=stage/'usr/share/fonts/truetype/noto';noto.mkdir(parents=True)
for font in Path('/usr/share/fonts/truetype/noto').glob('NotoSans-*.ttf'):
 shutil.copy2(font,noto/font.name)
fontconfig=stage/'usr/etc/fonts' ;fontconfig.mkdir(parents=True)
(fontconfig/'fonts.conf').write_text('<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd"><fontconfig><dir prefix="relative">../../share/fonts</dir><cachedir prefix="xdg">fontconfig</cachedir><alias><family>sans-serif</family><prefer><family>DejaVu Sans</family></prefer></alias><alias><family>SansSerif</family><prefer><family>DejaVu Sans</family></prefer></alias><alias><family>monospace</family><prefer><family>DejaVu Sans Mono</family></prefer></alias><alias><family>serif</family><prefer><family>DejaVu Serif</family></prefer></alias></fontconfig>')
# Follow ELF dependencies for every binary and dynamically loaded Qt/Python module.
skip=re.compile(r'^(?:ld-linux.*|lib(?:c|m|pthread|dl|rt|resolv|util|anl|nss_.*)\.so(?:\..*)?)$')
queue=[p for p in stage.rglob('*') if p.is_file() and (p.suffix=='.so' or '.so.' in p.name or p.parent==bin_dir)]
seen=set()
while queue:
 path=queue.pop()
 result=subprocess.run(['ldd',str(path)],capture_output=True,text=True)
 for line in result.stdout.splitlines():
  match=re.search(r'(?:=>\s*)?(/[^\s]+)',line)
  if not match:continue
  dep=Path(match.group(1))
  # Graphics userspace must match the host driver, particularly AMD/Mesa and NVIDIA.
  graphics=re.match(r'^lib(?:EGL.*|GL.*|OpenGL|gbm|drm.*|vulkan.*|glapi)\.so',dep.name)
  if skip.match(dep.name) or graphics or dep.name.startswith(("libstdc++", "libgcc_s")) or dep.name in seen:continue
  seen.add(dep.name);target=lib/dep.name
  if not target.exists():shutil.copy2(dep,target)
  queue.append(target)
# A static trampoline clears library paths before any host dynamic loader runs.
trampoline=build/'host-tool'
subprocess.run(['cc','-O2','-static','-s',str(src/'packaging/appimage/host-tool.c'),'-o',str(trampoline)],check=True)
for name in ('systemctl','nvidia-smi','xdg-open'):
 shutil.copy2(trampoline,bin_dir/name)
shutil.copy2(src/'plasmoid/contents/icons/vibeenergy.svg',stage/'vibeenergy.svg')
for name in ('AppRun','vibeenergy.desktop'):
 shutil.copy2(src/'packaging/appimage'/name,stage/name)
(stage/'AppRun').chmod(0o755)
(stage/'.DirIcon').symlink_to('vibeenergy.svg')
icon=stage/'usr/share/icons/hicolor/scalable/apps';icon.mkdir(parents=True,exist_ok=True)
shutil.copy2(stage/'vibeenergy.svg',icon/'vibeenergy.svg')
licenses=stage/'usr/share/vibeenergy/licenses';licenses.mkdir(parents=True)
for path in Path('/usr/share/doc').glob('*/copyright'):
 shutil.copy2(path,licenses/(path.parent.name+'.txt'))
for name in ('README.md','LICENSE'):
 shutil.copy2(src/name,stage/'usr/share/vibeenergy'/name)
subprocess.run(['dpkg-query','-W'],stdout=(stage/'usr/share/vibeenergy/build-packages.txt').open('w'),check=True)
print('Bundled libraries:',len(seen),flush=True)
