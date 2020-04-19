#!/bin/bash

########################
# Configure the options
########################

#
# speed at which to simulate typing. bigger num = faster
#
TYPE_SPEED=100

#
# custom prompt
#
# see http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/bash-prompt-escape-sequences.html for escape sequences
#
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W "

#
# custom colors
#
DEMO_CMD_COLOR="\033[0;37m"
DEMO_COMMENT_COLOR=$CYAN

DOCS_PATH=docs
START_TIME=$SECONDS

# put your demo awesomeness here
touch .lab.states

trap on_exit exit

function on_exit {
  elapsed_time=$(($SECONDS - $START_TIME))
  logger::info "Total elapsed time: $elapsed_time seconds"
}

function logger::info {
  # Cyan
  printf "\033[0;36mINFO\033[0m $@\n"
}

function logger::warn {
  # Yellow
  printf "\033[0;33mWARN\033[0m $@\n"
}

function logger::error {
  # Red
  printf "\033[0;31mERRO\033[0m $@\n"
  exit 1
}

DONE_COLOR="\033[0;36m"
QUES_COLOR="\033[0;33m"
CURR_COLOR="\033[0;37m"

function task::print-all {
  local task_dirs=($(ls -d -1 $DOCS_PATH/*/))

  for task_dir in ${task_dirs[@]}; do
    local has_task_or_step=0

    task::print $task_dir && has_task_or_step=1

    local step_files=($(find ${task_dir%/} -maxdepth 1 -name "*.md" -type f | sort | grep -v README))
    for step_file in ${step_files[@]}; do
      task::print $step_file && has_task_or_step=1
    done

    [[ $has_task_or_step == 1 ]] && echo
  done

  echo "To run a specific task or step, find the task or step id, and run $0 <task> <step>."
  echo
}

function task::print {
  local task=${1#*/}
  task=${task%/*}

  local step=${1##*/}
  step=${step%.md}

  local file=$1
  if [[ -n $task && -z $step ]]; then
    file="$1README.md"
  fi

  if [[ -f $file ]]; then
    local head_line="$(head -n 1 $file)"

    if [[ $head_line =~ ^#" " ]]; then
      local state

      if [[ -n $task && -n $step ]] && cat .lab.states | grep -q -e "^.\? $task $step"; then
        state=$(cat .lab.states | grep -e "^.\? $task $step")
        state=${state% $task $step}
      fi

      case $state in
      "*")
        head_line="${CURR_COLOR}$(echo $head_line | sed -e "s/^#/ ➞ /g")${COLOR_RESET}"
        ;;
      "v")
        head_line="${DONE_COLOR}$(echo $head_line | sed -e "s/^#/[✓]/g")${COLOR_RESET}"
        ;;
      "?")
        head_line="${QUES_COLOR}$(echo $head_line | sed -e "s/^#/[?]/g")${COLOR_RESET}"
        ;;
      *)
        if [[ -n $task && -n $step ]]; then
          head_line="$(echo $head_line | sed -e "s/^#/[ ]/g")"
        else
          head_line="$(echo $head_line | sed -e "s/^#/   /g")"
        fi
        ;;
      esac

      if [[ -n $task && -n $step ]]; then
        echo -e "$head_line [$task $step]"
      else
        echo -e "$head_line [$task]"
      fi
    fi
  else
    return 1
  fi
}

function task::run {
  local task=$1
  local step=$2
  local file="$DOCS_PATH/README.md"
  if [[ -n $task && -z $step ]]; then
    file="$DOCS_PATH/$task/README.md"
  elif [[ -n $task && -n $step ]]; then
    file="$DOCS_PATH/$task/$step.md"
  fi

  if [[ -f $file ]]; then
    task::run-with-logs $file $task $step
  fi

  local task_dir=$(dirname $file)
  if [[ -z $step && -d $task_dir ]]; then
    local step_files=($(find ${task_dir} -maxdepth 1 -name "*.md" -type f | sort | grep -v README))
    for file in ${step_files[@]}; do
      step=${file##*/}
      step=${step%.md}
      task::run-with-logs $file $task $step
    done
  fi
}

function task::run-with-logs {
  local file=$1
  local task=$2
  local step=$3
  if [[ -n $task && -n $step ]]; then
    sed -e "s/^*/?/g" .lab.states > .lab.states.tmp
    mv .lab.states{.tmp,}

    if cat .lab.states | grep -q -e "^.\? $task $step"; then
      sed -e "s/^? $task $step/* $task $step/g" \
          -e "s/^v $task $step/* $task $step/g" \
        .lab.states > .lab.states.tmp
      mv .lab.states{.tmp,}
    else
      echo "* $task $step" >> .lab.states
    fi
  fi

  if task::run-file $file && [[ -n $task && -n $step ]]; then
    sed -e "s/^* $task $step/v $task $step/g" .lab.states > .lab.states.tmp
    mv .lab.states{.tmp,}
  fi
}

function task::run-file {
  local file=$1
  if [[ -f $file ]]; then
    # print title
    p "$(head -n 1 $file)"

    # read lines
    local lines=()
    while IFS= read -r line; do
      lines+=("$line");
    done < $file

    # print content
    local summary=1
    local code=0
    local shell=0
    local hidden=0

    for line in "${lines[@]:1}"; do
      # reach the end of summary
      if [[ $line == --- && $summary == 1 ]]; then
        summary=0
        continue
      fi

      # print summary
      if [[ $summary == 1 ]]; then
        echo "  $line" | \
          sed -e 's%!\[\(.*\)\](.*)%\1 (See online version of the lab instructions)%g' \
              -e 's%\[\(.*\)\](.*)%\1%g'
      # print details
      else
        # skip empty line
        if [[ -z $line ]]; then
          continue;
        fi

        if [[ $line == \`\`\` ]]; then
          # reach the start of code
          if [[ $code == 0 && $shell == 0 ]]; then
            code=1
          # reach the end of code or shell
          else
            code=0
            shell=0
          fi
          continue
        # reach the start of shell
        elif [[ $line == \`\`\`shell && $shell == 0 ]]; then
          shell=1
          continue
        # reach the start of hidden
        elif [[ $line =~ ^\<!-- ]]; then
          hidden=1
          continue
        # reach the end of hidden
        elif [[ $line =~ ^--\> ]]; then
          hidden=0
          continue
        fi

        # print shell
        if [[ $shell == 1 ]]; then
          pe "$line"
        # print code
        elif [[ $code == 1 ]]; then
          echo "$line"
        elif [[ $hidden == 1 ]]; then
          eval "$line"
        # print normal text
        else
          p "## $line"
        fi
      fi
    done
  else
    p "## $@"
  fi
  
  echo
}

function task::main {
  local POSITIONAL=()
  local print_all=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -l)
      print_all=1
      shift
      ;;
    -c)
      clear
      shift
      ;;
    -d)
      DOCS_PATH=$2
      shift
      shift
      ;;
    -g)
      NO_WAIT=true
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
    esac
  done

  if [[ $print_all == 1 ]]; then
    task::print-all
  else
    task::run "${POSITIONAL[@]}"
  fi
}

function var::set {
  local message=$1
  local field=$2
  echo -n -e "${CYAN}? ${DEMO_CMD_COLOR}${message}${COLOR_RESET}"

  local current_value=$(eval echo \$${field})
  if [[ -n $current_value ]]; then
    echo -n -e "(${current_value}): "
  else
    echo -n -e ": "
  fi

  local new_value
  read -r new_value
  if [[ -n $new_value ]]; then
    eval ${field}=\'$new_value\'
  else
    return 1
  fi
}

function var::set-required {
  var::set "$@"
  while [[ -z $(eval echo \$$2) ]]; do
    var::set "$@"
  done
}

function var::save {
  local field=$1
  local value="$(eval echo \$${field})"
  sed -e "s#^${field}=.*#${field}='${value}'#g" .lab.settings > .lab.settings.tmp
  mv .lab.settings{.tmp,}
}