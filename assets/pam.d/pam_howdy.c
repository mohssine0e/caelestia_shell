#include <security/pam_modules.h>
#include <security/pam_ext.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <pwd.h>

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    const char *user = NULL;
    pam_get_item(pamh, PAM_USER, (const void **)&user);
    if (!user || !*user) {
        user = getenv("USER");
    }
    if (!user || !*user) {
        struct passwd *pw = getpwuid(getuid());
        if (pw) {
            user = pw->pw_name;
        }
    }
    if (!user || !*user) {
        pam_get_user(pamh, &user, NULL);
    }
    if (!user || !*user) {
        return PAM_USER_UNKNOWN;
    }

    const char *script = "/home/mohssine/.config/quickshell/caelestia/scripts/face_compare.py";
    if (access(script, X_OK) != 0 && access(script, R_OK) != 0) {
        script = "/usr/lib/security/howdy/compare.py";
    }

    pid_t pid = fork();
    if (pid == -1) {
        return PAM_SYSTEM_ERR;
    }
    if (pid == 0) {
        execl("/usr/bin/python3", "python3", script, user, (char *)NULL);
        _exit(1);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) == -1) {
        return PAM_SYSTEM_ERR;
    }

    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        return PAM_SUCCESS;
    }

    return PAM_AUTH_ERR;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    return PAM_SUCCESS;
}
