# ================================================================
# OS-specific configuration
# ================================================================

if [[ -f /etc/os-release ]]; then
  source /etc/os-release
fi


case "$ID" in
  fedora|ubuntu|debian)
    alias vim='gvim -v'
    ;;
esac
