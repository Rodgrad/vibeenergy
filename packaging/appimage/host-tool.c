/* Statically linked trampoline: host tools must never start with bundled libraries. */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {
    (void)argc;
    const char *name=strrchr(argv[0],'/');name=name?name+1:argv[0];
    if(strcmp(name,"systemctl") && strcmp(name,"nvidia-smi") && strcmp(name,"xdg-open"))return 127;
    const char *path=getenv("VIBEENERGY_HOST_PATH");
    if(path)setenv("PATH",path,1);
    const char *keys[]={"LD_LIBRARY_PATH","LD_PRELOAD","PYTHONHOME","PYTHONPATH","QT_PLUGIN_PATH","QT_QPA_PLATFORM_PLUGIN_PATH","QML_IMPORT_PATH","QML2_IMPORT_PATH","FONTCONFIG_FILE","FONTCONFIG_PATH",NULL};
    for(int i=0;keys[i];++i)unsetenv(keys[i]);
    char executable[128];snprintf(executable,sizeof(executable),"/usr/bin/%s",name);
    execv(executable,argv);perror(executable);return 127;
}
