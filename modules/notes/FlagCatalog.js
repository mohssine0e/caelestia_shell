.pragma library

var CATALOG = {
    "docker": {
        "-d": "Run container in background (detached mode) and print container ID",
        "--detach": "Run container in background (detached mode) and print container ID",
        "-p": "Publish container port(s) to host (format: HOST_PORT:CONTAINER_PORT)",
        "--publish": "Publish container port(s) to host (format: HOST_PORT:CONTAINER_PORT)",
        "-v": "Bind mount a storage volume or directory into the container",
        "--volume": "Bind mount a storage volume or directory into the container",
        "--rm": "Automatically remove container file system when it exits",
        "-i": "Keep STDIN open even if not attached",
        "--interactive": "Keep STDIN open even if not attached",
        "-t": "Allocate a pseudo-TTY for terminal access",
        "--tty": "Allocate a pseudo-TTY for terminal access",
        "-it": "Interactive terminal session (combines -i interactive and -t TTY)",
        "--name": "Assign a custom name to the container",
        "-e": "Set environment variable inside container (KEY=value)",
        "--env": "Set environment variable inside container (KEY=value)",
        "--network": "Connect container to a custom network (bridge, host, overlay)",
        "-a": "Show all containers, including stopped ones",
        "--all": "Show all containers, including stopped ones",
        "-q": "Quiet mode: print only numeric container/image IDs",
        "--quiet": "Quiet mode: print only numeric container/image IDs",
        "-f": "Force removal of a running container or force execution",
        "--force": "Force removal of a running container or force execution",
        "--tail": "Number of lines to show from end of container logs",
        "--build-arg": "Set build-time variable for Dockerfile",
        "--no-cache": "Do not use cached layers when building image"
    },
    "git": {
        "-b": "Create and switch to a new branch",
        "-m": "Set commit message",
        "--message": "Set commit message",
        "-am": "Stage all tracked modified files and commit with message",
        "-a": "Automatically stage modified and deleted files",
        "--all": "Apply operation to all branches or stage all files",
        "-p": "Interactive patch mode: review and select hunks individually",
        "--patch": "Interactive patch mode: review and select hunks individually",
        "-f": "Force overwrite remote branch history (destructive!)",
        "--force": "Force overwrite remote branch history (destructive!)",
        "--rebase": "Reapply commits on top of another base branch instead of creating a merge commit",
        "--no-ff": "Create a merge commit even if fast-forward is possible",
        "--ff-only": "Refuse to merge unless fast-forward is possible",
        "-d": "Delete branch safely only if already merged",
        "-D": "Force delete branch even if unmerged",
        "-u": "Set default remote upstream tracking branch for push/pull",
        "--set-upstream": "Set default remote upstream tracking branch for push/pull",
        "--hard": "Reset working tree and index; discards all uncommitted changes",
        "--soft": "Reset HEAD only; keeps changes staged in the index",
        "--global": "Apply configuration globally to current user (~/.gitconfig)",
        "--amend": "Amend previous commit with staged changes or updated message",
        "--oneline": "Format each commit as a single condensed line",
        "--graph": "Draw text-based ASCII graphical commit tree",
        "-S": "Search for commits that added or removed specific string",
        "--prune": "Prune deleted remote branches from local tracking list",
        "--abort": "Abort in-progress merge, rebase, or cherry-pick and restore previous state",
        "--continue": "Continue merge, rebase, or cherry-pick after resolving conflicts",
        "-fd": "Force clean untracked files and directories (-f force, -d directories)",
        "-n": "Dry run: preview changes without actually applying them"
    },
    "gh": {
        "-f": "Pass parameter key=value to workflow dispatch",
        "-r": "Specify branch or tag ref to run workflow on",
        "--json": "Output data formatted as JSON",
        "-w": "Open target in default web browser",
        "--web": "Open target in default web browser",
        "--repo": "Target specific repository (OWNER/REPO)"
    },
    "pacman": {
        "-S": "Sync and install package from remote repositories",
        "-Syu": "Synchronize database and upgrade all installed packages",
        "-R": "Remove specified package",
        "-Rns": "Remove package, its unneeded dependencies, and configuration files",
        "-Q": "Query installed packages locally",
        "-Qe": "List explicitly installed packages",
        "-Ss": "Search remote repositories for matching packages",
        "-Si": "Show detailed remote package information"
    },
    "cargo": {
        "--release": "Build with optimizations for production release",
        "--bin": "Build or run specified binary target in crate",
        "--example": "Build or run specified example in crate",
        "-p": "Target specific package in a cargo workspace",
        "--package": "Target specific package in a cargo workspace",
        "-q": "Quiet mode: suppress non-error cargo messages",
        "--quiet": "Quiet mode: suppress non-error cargo messages"
    },
    "systemctl": {
        "--user": "Manage user-level services rather than system services",
        "--now": "Start/stop the service immediately in addition to enable/disable",
        "-l": "Do not truncate unit names or log messages",
        "--full": "Do not truncate unit names or log messages",
        "--no-pager": "Do not pipe command output to less or pager"
    },
    "rabbitmqadmin": {
        "-u": "Username for RabbitMQ management API",
        "-p": "Password for RabbitMQ management API",
        "-H": "Host address of RabbitMQ server",
        "-V": "Virtual host (vhost) to operate on"
    }
};

var CONTEXTUAL = {
    "git": {
        "log": { "-p": "Show the patch introduced by each commit.", "--patch": "Show the patch introduced by each commit." },
        "add": { "-p": "Interactively choose which changes to stage.", "--patch": "Interactively choose which changes to stage." },
        "push": { "-f": "Overwrite the remote branch; this can discard others' published commits.", "--force": "Overwrite the remote branch; this can discard others' published commits." },
        "branch": { "-d": "Delete a branch only when Git considers it merged.", "-D": "Force-delete a branch even if it is not merged." },
        "commit": { "-a": "Stage tracked modifications and deletions before committing." }
    },
    "docker": {
        "ps": { "-a": "Include stopped containers in the container list.", "--all": "Include stopped containers in the container list." },
        "run": { "-d": "Start the container in the background and print its ID." },
        "logs": { "--tail": "Show only the requested number of final log lines." },
        "build": { "--no-cache": "Build without reusing cached layers." }
    },
    "kubectl": {
        "get": { "-o": "Choose the output format for the selected Kubernetes resources." },
        "apply": { "-f": "Read desired resources from the specified file or URL." },
        "logs": { "-f": "Stream new log lines as they are written." }
    }
};

var KNOWN_SUBCOMMANDS = {
    "git": ["add", "branch", "checkout", "cherry-pick", "commit", "diff", "fetch", "log", "merge", "pull", "push", "rebase", "reset", "restore", "show", "status", "switch", "tag"],
    "docker": ["build", "compose", "exec", "images", "inspect", "logs", "ps", "pull", "rm", "rmi", "run", "start", "stop", "volume"],
    "kubectl": ["apply", "config", "create", "delete", "describe", "exec", "get", "logs", "port-forward", "rollout", "scale", "set", "top"],
    "podman": ["build", "exec", "images", "inspect", "logs", "ps", "pull", "rm", "run", "start", "stop"],
    "cargo": ["add", "build", "check", "clippy", "fmt", "install", "run", "test", "update"],
    "gh": ["auth", "issue", "pr", "release", "repo", "run", "workflow"]
};

function getExplanation(tool, flag, subcommand) {
    if (!flag) return "";
    var cleanTool = String(tool || "").trim().toLowerCase();
    var cleanFlag = String(flag || "").trim();

    var cleanSubcommand = String(subcommand || "").trim().toLowerCase();

    // 1. The most specific command context wins.
    if (CONTEXTUAL[cleanTool] && CONTEXTUAL[cleanTool][cleanSubcommand]
            && CONTEXTUAL[cleanTool][cleanSubcommand][cleanFlag]) {
        return CONTEXTUAL[cleanTool][cleanSubcommand][cleanFlag];
    }

    // 2. Direct tool match
    if (CATALOG[cleanTool] && CATALOG[cleanTool][cleanFlag]) {
        return CATALOG[cleanTool][cleanFlag];
    }

    // 3. Fallback for compound short flags like -am, -it, -fd
    if (cleanFlag.startsWith("-") && !cleanFlag.startsWith("--") && cleanFlag.length > 2) {
        var parts = [];
        for (var i = 1; i < cleanFlag.length; i++) {
            var single = "-" + cleanFlag[i];
            var exp = getExplanation(cleanTool, single);
            if (exp) parts.push(single + ": " + exp);
        }
        if (parts.length > 0) return parts.join(" | ");
    }

    return "";
}

function parseTokens(cmd) {
    var raw = String(cmd || "").trim().replace(/^\$\s*/, "");
    var parts = raw.split(/\s+/).filter(function(part) { return !!part; });
    var wrappers = ["sudo", "doas", "command", "exec", "time", "nice", "env"];
    var toolIndex = 0;
    while (toolIndex < parts.length && wrappers.indexOf(parts[toolIndex]) >= 0) toolIndex++;
    while (toolIndex < parts.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(parts[toolIndex])) toolIndex++;
    var tool = toolIndex < parts.length ? parts[toolIndex].split("/").pop().toLowerCase() : "";
    var subcommand = "";
    var allowed = KNOWN_SUBCOMMANDS[tool] || [];
    for (var commandIndex = toolIndex + 1; commandIndex < parts.length; commandIndex++) {
        if (allowed.indexOf(parts[commandIndex]) >= 0) {
            subcommand = parts[commandIndex];
            break;
        }
    }
    var tokens = [];

    for (var i = 0; i < parts.length; i++) {
        var p = parts[i];
        if (!p) continue;
        var isFlag = /^--?[A-Za-z0-9][\w-]*/.test(p);
        tokens.push({
            text: p,
            isFlag: isFlag,
            tool: tool,
            subcommand: subcommand
        });
    }
    return tokens;
}
