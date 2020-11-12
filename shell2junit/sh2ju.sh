#!/usr/bin/env bash
### Copyright 2010 Manuel Carrasco Moñino. (manolo at apache.org)
###
### Forked from:
### https://github.com/kubernetes/kubernetes/blob/master/third_party/forked/shell2junit/sh2ju.sh
###
### Licensed under the Apache License, Version 2.0.
### You may obtain a copy of it at
### http://www.apache.org/licenses/LICENSE-2.0

###
### A library for shell scripts which creates reports in jUnit format.
### These reports can be used in Jenkins, or any other CI.
###
### Usage:
###     - Include this file in your shell script
###     - Use juLog to call your command any time you want to produce a new report
###        Usage:   juLog <options> command arguments
###           options:
###             -class="MyClass"       : a class name which will be shown in the junit report
###             -name="TestName"       : the test name which will be shown in the junit report
###             -error="RegExp"        : a regexp which sets the test as failure when the output matches it
###             -ierror="RegExp"       : same as -error but case insensitive
###             -output="OutputDir"    : path of output directory, defaults to "./results"
###             -file="OutputFile"     : name of output file, defaults to "junit.xml"
###             -index                 : add incremental test index (e.g. for alphabetical sort in Jenkins)
###     - Junit reports are left in the folder 'result' under the directory where the script is executed.
###     - Configure Jenkins to parse junit files from the generated folder
###

# set +e - To avoid breaking the calling script, if juLog has internal error (e.g. in SED)
set +e

# set +x - To avoid printing commands in debug mode
set +x

asserts=00; errors=0; suiteDuration=0; content=""
date="$(which gdate 2>/dev/null || which date)"

# default output directory and file
juDIR="$(pwd)/results"
juFILE="junit.xml"
export sortTests=""
export testIndex=0

if LANG=C sed --help 2>&1 | grep -q GNU; then
  SED="sed"
elif which gsed &>/dev/null; then
  SED="gsed"
else
  echo "Failed to find GNU sed as sed or gsed. If you are on Mac: brew install gnu-sed." >&2
  exit 1
fi

# A wrapper for the eval method witch allows catching seg-faults and use tee
errfile=/tmp/evErr.$$.log
# :>${errfile}
# errfile=$(mktemp /tmp/ev_err_log_XXXXXX)

function eVal() {
  (eval "$1")
  # stdout and stderr may currently be inverted (see below) so echo may write to stderr
  echo "$?" 2>&1 | tr -d "\n" > "${errfile}"
}

# TODO: Use this function to clean old test results (xmls)
function juLogClean() {
  echo "+++ Removing old junit reports from: ${juDIR} "
  find ${juDIR} -maxdepth 1 -name "${juFILE}" -delete
}

# Function to print text file without special characters and ansi colors
function printPlainTextFile() {
  local data_file="$1"
  # echo "$(tr -dC '[:print:]\t\n' < "$data_file")" > "$data_file"
  # sed -r 's:\[[0-9;]+[mK]::g' "$data_file"

  while read line ; do
    echo "$line" | tr -dC '[:print:]\t\n' | sed -r 's:\[[0-9;]+[mK]::g'
  done < "$data_file"
}

function juLogClean() {
  echo "+++ Removing old junit reports from: ${juDIR} "
  find ${juDIR} -maxdepth 1 -name "${juFILE}" -delete
}

# Execute a command and record its results
function juLog() {

  # In case of script error: Exit with the real return code of eVal()
  export exitCode=0
  trap 'exit $(eval $exitCode)' ERR # RETURN EXIT HUP INT TERM

  errfile=/tmp/evErr.$$.log
  # tmpdir="/var/tmp"
  # errfile=`mktemp "$tmpdir/ev_err_log_XXXXXX"`

  date="$(which gdate 2>/dev/null || which date || :)"
  asserts=00; errors=0; suiteDuration=0; content=""
  export testIndex=$(( testIndex+1 ))

  # parse arguments
  ya=""; icase=""
  while [[ -z "$ya" ]]; do
    case "$1" in
      -class=*)  class="$(echo "$1" | ${SED} -e 's/-class=//')";   shift;;
      -name=*)   name="$(echo "$1" | ${SED} -e 's/-name=//')";   shift;;
      -ierror=*) ereg="$(echo "$1" | ${SED} -e 's/-ierror=//')"; icase="-i"; shift;;
      -error=*)  ereg="$(echo "$1" | ${SED} -e 's/-error=//')";  shift;;
      -output=*) juDIR="$(echo "$1" | ${SED} -e 's/-output=//')";  shift;;
      -file=*)   juFILE="$(echo "$1" | ${SED} -e 's/-file=//')";  shift;;
      -index)    sortTests="$(echo "$1" | ${SED} -e 's/-index/TRUE/')";  shift;;
      *)         ya=1;;
    esac
  done

  if [[ "${class}" = "" ]]; then
    class="default"
  fi

  # Set test suite title to class name with uppercase letter and spaces
  suiteTitle=( "${class//[_.]/ }" )
  suiteTitle="${suiteTitle[@]^}"

  # set output file name as class name, if it was not given
  juFILE="${class}_junit.xml"

  # create output directory
  mkdir -p "${juDIR}" || exit
  # use first arg as name if it was not given
  if [[ -z "${name}" ]]; then
    name="${asserts}-$1"
    shift
  fi

  if [[ ! -e "${juDIR}/${juFILE}" ]]; then
    # no Junit file exists. Adding a new file
    cat <<EOF > "${juDIR}/${juFILE}"
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
    <testsuite name="${suiteTitle}" tests="0" assertions="" failures="0" errors="0" time="0">
    </testsuite>
</testsuites>
EOF
  fi

  # calculate command to eval
  [[ -z "$1" ]] && return
  cmd="$1"; shift
  while [[ -n "${1:-}" ]]
  do
     cmd="${cmd} \"$1\""
     shift
  done

  # eval the command sending output to a file
  outf=/var/tmp/ju$$.txt
  errf=/var/tmp/ju$$-err.txt
  # outf=`mktemp "$tmpdir/ju_txt_XXXXXX"`
  # errf=`mktemp "$tmpdir/ju_err_XXXXXX"`

  :>${outf}

  echo ""                         | tee -a ${outf}
  echo "+++ Running case${testIndex:+ ${testIndex}}: ${class}.${name} " # | tee -a ${outf}
  echo "+++ Working directory: $(pwd)"           # | tee -a ${outf}
  echo "+++ Command: ${cmd}"            # | tee -a ${outf}
  ini="$(${date} +%s.%N)"
  # execute the command, temporarily swapping stderr and stdout so they can be tee'd to separate files,
  # then swapping them back again so that the streams are written correctly for the invoking process
  ( (eVal "${cmd}" | tee -a ${outf}) 3>&1 1>&2 2>&3 | tee ${errf}) 3>&1 1>&2 2>&3

  exitCode="$([[ -s "$errfile" ]] && cat "$errfile" || echo "1")"
  rm -f "${errfile}"
  end="$(${date} +%s.%N)"

  # Workaround for "Argument list too long" memory errors
  # ulimit -s 65536

  # Save output and error messages without special characters (e.g. ansi colors), and delete their temp files
  outMsg="$(printPlainTextFile "$outf")"
  rm -f ${outf} || :
  errMsg="$(printPlainTextFile "$errf")"
  rm -f ${errf} || :

  # set the appropriate error, based in the exit code and the regex
  [[ ${exitCode} != 0 ]] && isErr=1 || isErr=0
  if [ ${isErr} = 0 ] && [ -n "${ereg:-}" ]; then
      H=$(echo "${outMsg}" | grep -E ${icase} "${ereg}")
      [[ -n "${H}" ]] && isErr=1
  fi
  [[ ${isErr} != 0 ]] && echo "+++ Error: ${exitCode}"        # | tee -a ${outf}

  # calculate vars
  asserts=$((asserts+1))
  errors=$((errors+isErr))
  testDuration=$(echo "${end} ${ini}" | awk '{print $1 - $2}')
  suiteDuration=$(echo "${suiteDuration} ${testDuration}" | awk '{print $1 + $2}')

  # Set test title with uppercase letter and spaces
  testTitle=( ${name//_/ } )
  testTitle="${testTitle[@]^}"

  if [[ -n "$sortTests" ]] ; then
    # Add zero-padding digits to testIndex in title
    digits=000
    zero_padding="$digits$testIndex"
    testTitle="${zero_padding:(-${#digits})} : ${testTitle}"
  fi

  # write the junit xml report
  ## system-out or system-err tag
  if [[ ${isErr} = 0 ]] ; then
    output="
    <system-out><![CDATA[${outMsg}]]></system-out>
    "
  else
    output="
    <failure type=\"ScriptError\" message=\"Failure in ${class}.${name}\">
    <![CDATA[${outMsg}]]>
    </failure>
    <system-err><![CDATA[${errMsg}]]></system-err>
    "
  fi

  ## testcase tag
  content="${content}
    <testcase assertions=\"1\" name=\"${testTitle}\" time=\"${testDuration}\" classname=\"${suiteTitle}\">
    ${output}
    </testcase>
  "
  ## testsuite block

  if [[ -e "${juDIR}/${juFILE}" ]]; then
    # file exists. first update the failures count
    failCount=$(${SED} -n "s/.*testsuite.*failures=\"\([0-9]*\)\".*/\1/p" "${juDIR}/${juFILE}")
    errors=$((failCount+errors))
    ${SED} -i "0,/failures=\"${failCount}\"/ s/failures=\"${failCount}\"/failures=\"${errors}\"/" "${juDIR}/${juFILE}"
    ${SED} -i "0,/errors=\"${failCount}\"/ s/errors=\"${failCount}\"/errors=\"${errors}\"/" "${juDIR}/${juFILE}"

    # file exists. Need to append to it. If we remove the testsuite end tag, we can just add it in after.
    ${SED} -i "s^</testsuite>^^g" "${juDIR}/${juFILE}" ## remove testSuite so we can add it later
    ${SED} -i "s^</testsuites>^^g" "${juDIR}/${juFILE}"
    cat <<EOF >> "$juDIR/${juFILE}"
     ${content:-}
    </testsuite>
</testsuites>
EOF

    # Update suite summary on the first <testsuite> tag:
    sed -e "0,/<testsuite .*>/s/<testsuite .*>/\
    <testsuite name=\"${suiteTitle}\" tests=\"${testIndex}\" assertions=\"${assertions:-}\" failures=\"${errors}\" errors=\"${errors}\" time=\"${suiteDuration}\">/" -i "${juDIR}/${juFILE}"
  fi

  # set -e # set -o errexit
  set -e
  return ${exitCode}
}
