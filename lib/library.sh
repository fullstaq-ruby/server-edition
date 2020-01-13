RESET=$'\033[0m'
BOLD=$'\033[1m'
YELLOW=$'\033[33m'
# shellcheck disable=SC2034
CYAN=$'\033[36m'
BLUE_BG=$'\033[44m'

if [[ "$VERBOSE" = "" ]]; then
    VERBOSE=false
fi

function header()
{
    local title="$1"
    echo "${BLUE_BG}${YELLOW}${BOLD}${title}${RESET}"
    echo "------------------------------------------"
}

function run()
{
    echo "+ $*"
    "$@"
}

function verbose_run()
{
    if $VERBOSE; then
        echo "+ $*"
    fi
    "$@"
}

function verbose_exec()
{
    if $VERBOSE; then
        echo "+ $*"
    fi
    exec "$@"
}

# A single-value file is a file such as environments/ubuntu-18.04/image_tag.
# It contains exactly 1 line of usable value, and may optionally contain
# comments that start with '#', which are ignored.
function read_single_value_file()
{
    grep -v '^#' "$1" | head -n 1
}

function require_args_exact()
{
    local count="$1"
    shift
    if [[ $# -ne $count ]]; then
        echo "ERROR: $count arguments expected, but got $#."
        exit 1
    fi
}

function require_envvar()
{
    local name="$1"
    local value=$(eval "echo \$$name")
    if [[ "$value" = "" ]]; then
        echo "ERROR: please pass the '$name' environment variable to this script."
        exit 1
    fi
}

function require_container_envvar()
{
    local name="$1"
    local value=$(eval "echo \$$name")
    if [[ "$value" = "" ]]; then
        echo "ERROR: please pass the '$name' environment variable to the container."
        exit 1
    fi
}

function require_container_mount()
{
    local path="$1"
    if [[ ! -e "$path" ]]; then
        echo "ERROR: please ensure $path is mounted in the container."
        exit 1
    fi
}

if command -v realpath &>/dev/null; then
    function absolute_path()
    {
        realpath -L "$1"
    }
else
    function absolute_path()
    {
        local dir
        local name

        dir=$(dirname "$1")
        name=$(basename "$1")
        dir=$(cd "$dir" && pwd)
        echo "$dir/$name"
    }
fi

function list_environment_names()
{
    ls -1 "$1" | grep -v '^utility$' | sort | xargs echo
}

function create_file_if_missing()
{
    if [[ ! -e "$1" ]]; then
        run touch "$1"
    fi
}

function cleanup()
{
    set +e
    local pids
    pids=$(jobs -p)
    if [[ "$pids" != "" ]]; then
        # shellcheck disable=SC2086
        kill $pids 2>/dev/null
    fi
    if [[ $(type -t _cleanup) == function ]]; then
        _cleanup
    fi
}

trap cleanup EXIT
