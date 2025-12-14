#!/usr/bin/env bash
# vrecord-completion.bash - Bash completion for vrecord
#
# Installation:
#   1. Source this file in your ~/.bashrc or ~/.bash_profile:
#      source /path/to/vrecord-completion.bash
#
#   2. Or copy to system completion directory:
#      sudo cp vrecord-completion.bash /etc/bash_completion.d/vrecord
#
# Features:
#   - Complete commands and options
#   - Smart context-aware completions
#   - File completion for -r/--resume
#   - Option completion based on context

_vrecord_completions() {
  local cur prev words cword
  _init_completion || return

  local commands="start pause resume stop status list help"
  local global_opts="-n --no-mp3 -b --no-beep -v --verbose -q --quiet -h --help -V --version"

  # Get the command if one has been specified
  local cmd=""
  local i
  for ((i=1; i < cword; i++)); do
    if [[ " $commands " == *" ${words[i]} "* ]]; then
      cmd="${words[i]}"
      break
    fi
  done

  # If we're still looking for a command
  if [[ -z "$cmd" ]]; then
    case "$prev" in
      -n|--no-mp3|-v|--verbose|-q|--quiet)
        # After global options, suggest commands
        mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
        return
        ;;
      *)
        # No command yet, show commands and global options
        if [[ "$cur" == -* ]]; then
          mapfile -t COMPREPLY < <(compgen -W "$global_opts" -- "$cur")
        else
          mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
        fi
        return
        ;;
    esac
  fi

  # Command-specific completions
  case "$cmd" in
    start)
      case "$prev" in
        start)
          # After 'start', could be prefix or options
          if [[ "$cur" == -* ]]; then
            mapfile -t COMPREPLY < <(compgen -W "-c --continue-last -r --resume -t --transcribe" -- "$cur")
          else
            # Suggest some common prefixes
            mapfile -t COMPREPLY < <(compgen -W "interview meeting lecture podcast note" -- "$cur")
          fi
          ;;
        -r|--resume)
          # Complete with WAV files from recording directory
          local recording_dir="${RECORDING_DIR:-$HOME/Recordings}"
          if [[ -d "$recording_dir" ]]; then
            # Get basenames of WAV files using find (safer than ls)
            local files
            files=$(find "$recording_dir" -maxdepth 1 -name '*.wav' -printf '%f\n' 2>/dev/null | sed 's/\.wav$//')
            mapfile -t COMPREPLY < <(compgen -W "$files" -- "$cur")
          fi
          ;;
        -c|--continue-last)
          # No more arguments after -c
          COMPREPLY=()
          ;;
        *)
          # Could be prefix after other args
          if [[ "$cur" != -* ]] && [[ "$prev" != "-r" ]] && [[ "$prev" != "--resume" ]]; then
            mapfile -t COMPREPLY < <(compgen -W "interview meeting lecture podcast note" -- "$cur")
          fi
          ;;
      esac
      ;;

    list)
      case "$prev" in
        list)
          mapfile -t COMPREPLY < <(compgen -W "--all" -- "$cur")
          ;;
        *)
          COMPREPLY=()
          ;;
      esac
      ;;

    stop)
      case "$prev" in
        stop)
          if [[ "$cur" == -* ]]; then
            mapfile -t COMPREPLY < <(compgen -W "-t --transcribe" -- "$cur")
          else
            COMPREPLY=()
          fi
          ;;
        *)
          COMPREPLY=()
          ;;
      esac
      ;;

    pause|resume|status|help)
      # These commands take no arguments
      COMPREPLY=()
      ;;

    *)
      # Shouldn't get here, but just in case
      COMPREPLY=()
      ;;
  esac
}

# Register the completion function for vrecord
complete -F _vrecord_completions vrecord

# Also register for the full path if it's in PATH
if command -v vrecord >/dev/null 2>&1; then
  complete -F _vrecord_completions "$(command -v vrecord)"
fi

# vim: ft=bash
#fin
