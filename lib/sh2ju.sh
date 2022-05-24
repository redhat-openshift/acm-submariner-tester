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
###             -status="StatusFile"   : Continue/Skip further tests according to status file: 0 (OK), 1 (Critical failure: Skip rest), 2 (Failed but continue)
###             -index                 : add incremental test index (e.g. for alphabetical sort in Jenkins)
###     - Junit reports are left in the folder 'result' under the directory where the script is executed.
###     - Configure Jenkins to parse junit files from the generated folder
###

# set +e - To avoid breaking the calling script, if juLog has internal error (e.g. in SED)
set +e

# set +x - To avoid printing commands in debug mode
set +x

# Temporary files to store the command stdout, stderr and exit code
outf=$(mktemp)_ju.out
export outf
errf=$(mktemp)_ju.err
export errf
returnf=$(mktemp)_eval_rc.log
export returnf

# Temporary file to store Testcase tag content, that is added for each new testcase in the junit xml
newTestCaseTag=$(mktemp)_tc_content

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

# Function to execute command (like bash eval method), which allows catching seg-faults and use tee
# It saves output to temporary files: stdout > ${outf}, stderr > ${errf}, exit code > ${returnf}
function eVal() {
  # Execute the command, temporarily swapping stderr and stdout so they can be tee'd to separate files,
  # then swapping them back again so that the streams are written correctly for the invoking process
  echo 0 > "${returnf}"
  (
    (
      {
        trap 'RC=$? ; [[ "$RC" != 5 ]] || RC=0 ; echo $RC > "${returnf}" ; echo "+++ sh2ju command exit code: $RC" ; exit $RC' ERR;
        trap 'RC="$(< $returnf)" ; echo +++ sh2ju command termination code: $RC" ; exit $RC' HUP INT TERM;
        set -e; $1;
      } | tee -a "${outf}"
    ) 3>&1 1>&2 2>&3 | tee "${errf}"
  ) 3>&1 1>&2 2>&3
}

# TODO: Use this function to clean old test results (xmls)
function juLogClean() {
  echo "+++ sh2ju removing old junit reports from: ${juDir} "
  find "${juDir}" -maxdepth 1 -name "${juFile}" -delete
}

# Function to remove special characters and ansi colors from a text file
function convertToPlainTextFile() {
  local filePath="$1"
  ${SED} -r -e 's:\[[0-9;]+[mK]::g' -e 's/[^[:print:]\t\n]//g' -i "$filePath"
}


# Function to escape XML special characters from a text file
function excapeXML() {
  local filePath="$1"
  ${SED} -e 's/&/\&amp;/g' -e "s/\"/\&quot;/g" -e "s/'/\&apos;/g"  -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -i "$filePath"
}


# Execute a command and record its results
function juLog() {

  # set +e - To avoid breaking the calling script, if juLog has internal error (e.g. in SED)
  set +e

  # Workaround for "Argument list too long" memory errors
  # ulimit -s 65536

  # In case of script error: Exit with the last return code of eVal()
  export returnCode=0
  trap 'echo "+++ sh2ju exit code: $returnCode" ; exit $returnCode' HUP INT TERM # ERR RETURN EXIT HUP INT TERM

  local statusFile

  # Initialize testsuite attributes
  dateTime="$(which gdate 2>/dev/null || which date || :)"
  asserts=00; failures=0; skipped=0; suiteDuration=0; # content=""
  export testIndex=$(( testIndex+1 ))

  # parse arguments
  ya=""; icase=""
  while [[ -z "$ya" ]]; do
    case "$1" in
      -class=*)  class="$(echo "$1" | ${SED} -e 's/-class=//')";   shift;;
      -name=*)   name="$(echo "$1" | ${SED} -e 's/-name=//')";   shift;;
      -ierror=*) ereg="$(echo "$1" | ${SED} -e 's/-ierror=//')"; icase="-i"; shift;;
      -error=*)  ereg="$(echo "$1" | ${SED} -e 's/-error=//')";  shift;;
      -output=*) juDir="$(echo "$1" | ${SED} -e 's/-output=//')";  shift;;
      -file=*)   juFile="$(echo "$1" | ${SED} -e 's/-file=//')";  shift;;
      -status=*) statusFile="$(echo "$1" | ${SED} -e 's/-status=//')";  shift;;
      -index)    sortTests="$(echo "$1" | ${SED} -e 's/-index/TRUE/')";  shift;;
      *)         ya=1;;
    esac
  done

  if [[ "${class}" == "" ]]; then
    class="default"
  fi

  # Set testsuite title to class name with spaces (instead of _ ), and with uppercase words
  suiteTitle="${class//_/ }"
  suiteTitle="${suiteTitle[@]^}"

  # Set output directory as ./results , if it was not given
  juDir="${juDir:-$(pwd)/results}"

  # Set output file name as class name, if it was not given
  juFile="${juFile:-${class}_junit.xml}"

  # Set overall suite status, according to the content of status file
  # Should be either 0 (OK to continue tests), 1 (Critical failure: Skip rest of tests), 2 (Failed but continue)
  testSuiteStatus="$([[ ! -s "$statusFile" ]] || cat "$statusFile")"

  # Create output directory
  mkdir -p "${juDir}" || exit
  # Use first arg as name if it was not given
  if [[ -z "${name}" ]]; then
    name="${asserts}-$1"
    shift
  fi

  if [[ ! -e "${juDir}/${juFile}" ]]; then
    # no Junit file exists. Adding a new file
    cat <<EOF > "${juDir}/${juFile}"
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
    <testsuite name="${suiteTitle}" tests="0" assertions="" failures="0" errors="0" skipped="0" time="0">
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

  echo "+++ sh2ju running case${testIndex:+ ${testIndex}}: ${class}.${name} "
  echo "+++ sh2ju working directory: $(pwd)"
  echo "+++ sh2ju command: ${cmd}"
  echo "+++ sh2ju test suite status: ${testSuiteStatus} [${statusFile}]"
  # To print +++ sh2ju (debuging lines) into ${outf}, you can add: | tee -a ${outf}

  # Clear content of the temporary files
  : > "${outf}"
  : > "${errf}"
  : > "${returnf}"

  # Save datetime before executing the command
  testStartTime="$(${dateTime} +%s.%N)"

  ### If testSuiteStatus is not 1: Call eVal() to execute the test, and set suite status result 
  if [[ "$testSuiteStatus" != 1 ]] ; then
    # Run command and set the test return code, based on the command exit code
    eVal "${cmd}"
    returnCode="$([[ -s "$returnf" ]] && cat "$returnf" || echo "0")"

    if [[ "${returnCode}" != 0 ]] ; then
      # Command failed
      if [[ -f "$statusFile" ]] ; then
        # If suite status is empty - set status file to: 1 (Critical failure)
        [[ -n "$testSuiteStatus" ]] || echo 1 > "$statusFile"
        # If suite status is 0 (Pass) - set status file to: 2 (Failed but continue)
        [[ "$testSuiteStatus" != 0 ]] || echo 2 > "$statusFile"
      fi
      testCaseStatus=FAILED 
    else
      testCaseStatus=PASSED
    fi

  else
    # Since critical test failed before (testSuiteStatus = 1) - Skip this command
    cmd="echo 'Critical test failed before - Skipping: ${cmd}'"
    eVal "${cmd}"
    returnCode=0
    testCaseStatus=SKIP
  fi


  # Save datetime after executing the command
  testEndTime="$(${dateTime} +%s.%N)"

  # Convert $outf (stdout file) and $errf (stderr file) to plain text for XML data (e.g. without ansi colors)
  convertToPlainTextFile "${outf}" || :
  convertToPlainTextFile "${errf}" || :
  excapeXML "${outf}" || :
  excapeXML "${errf}" || :

  
  if [[ ${testCaseStatus} == PASSED ]] && [[ -n "${ereg:-}" ]]; then
    # Change testCaseStatus to FAILED if output includes regex of potential error
    if grep -q -E ${icase} "${ereg}" "${outf}" ; then
      testCaseStatus=FAILED
    fi
  elif [[ ${testCaseStatus} == FAILED ]] ; then
    # Increase the failures + 1
    failures=$((failures+1))
  elif [[ ${testCaseStatus} == SKIP ]] ; then
    # Increase the skipped + 1
    skipped=$((skipped+1))
  fi

  
  # Calculate test duration and counter
  asserts=$((asserts+1))
  testDuration=$(echo "${testEndTime} ${testStartTime}" | awk '{print $1 - $2}')
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

  # Write the junit xml report

  # Update testcase tag content file (not saving data in variables due to "Argument list too long" potential error)
  cat <<-EOF > "${newTestCaseTag}"
      <testcase assertions="1" name="${testTitle}" time="${testDuration}" classname="${class//./-}">
EOF

  # system-out tag if testcase passed
  if [[ ${testCaseStatus} == PASSED ]] ; then
    echo '    <system-out>' >> "${newTestCaseTag}"
    cat "${outf}" >> "${newTestCaseTag}"
    echo '    </system-out>' >> "${newTestCaseTag}"

  # Or skipped tag if testcase was skipped
  elif [[ ${testCaseStatus} == SKIP ]] ; then
    echo '    <skipped>' >> "${newTestCaseTag}"
    cat "${outf}" >> "${newTestCaseTag}"
    echo '    </skipped>' >> "${newTestCaseTag}"

  # Or failure and error tags if testcase failed
  else
    # Get failure summary from $errf, by removing empty lines from $errf + getting last 2 lines
    # failure_summary=$(grep "\S" "$errf" | tail -2 | sed -e "s/\"/'/g" -e 's/&/\&amp;/g' -e 's/</\&lt;/g')
    failure_summary=$(grep "\S" "$errf" | tail -2)

    echo "    <failure type=\"ScriptError\" message=\"${failure_summary}\">" >> "${newTestCaseTag}"
    cat "${outf}" >> "${newTestCaseTag}"
    echo '    </failure>' >> "${newTestCaseTag}"

    ## system-err tag in addition to failure tag
    echo '    <system-err>' >> "${newTestCaseTag}"
    cat "${errf}" >> "${newTestCaseTag}"
    echo '    </system-err>' >> "${newTestCaseTag}"

  fi

  ## testcase tag end
  echo '      </testcase>' >> "${newTestCaseTag}"

  # Testsuite block
  if [[ -e "${juDir}/${juFile}" ]]; then

    # Get the number of failures in existing junit.xml, and append current failures counter to it
    failCount=$(grep -Po -m1 'testsuite.*failures="\K[0-9]+' "${juDir}/${juFile}")
    [[ ! "$failCount" =~ ^[0-9]+$ ]] || failures=$((failCount+failures))

    # Get the number of skipped in existing junit.xml, and append current skipped counter to it
    skipCount=$(grep -Po -m1 'testsuite.*skipped="\K[0-9]+' "${juDir}/${juFile}")
    [[ ! "$skipCount" =~ ^[0-9]+$ ]] || skipped=$((skipCount+skipped))

    # Update the number of failures (and errors the same), and number of skipped tests, in the testsuite tag
    ${SED} -i "0,/failures=\"${failCount}\"/ s/failures=\"${failCount}\"/failures=\"${failures}\"/" "${juDir}/${juFile}"
    ${SED} -i "0,/errors=\"${failCount}\"/ s/errors=\"${failCount}\"/errors=\"${failures}\"/" "${juDir}/${juFile}"
    ${SED} -i "0,/skipped=\"${skipCount}\"/ s/skipped=\"${skipCount}\"/skipped=\"${skipped}\"/" "${juDir}/${juFile}"

    # In order to append the new testcase tag in the testsuite, remove the closing testsuite and testsuites end tags
    ${SED} -i "s^</testsuite>^^g" "${juDir}/${juFile}"
    ${SED} -i "s^</testsuites>^^g" "${juDir}/${juFile}"

    # Append the new testcase tag
    cat "${newTestCaseTag}" >> "${juDir}/${juFile}"

    # Testsuite (and testsuites) tags end
    cat <<-EOF >> "${juDir}/${juFile}"
    </testsuite>
</testsuites>
EOF

    # Update suite summary on the first <testsuite> tag:
    ${SED} -e "0,/<testsuite .*>/s/<testsuite .*>\s*/\
    <testsuite name=\"${suiteTitle}\" tests=\"${testIndex}\" assertions=\"${assertions:-}\" \
    failures=\"${failures}\" errors=\"${failures}\" skipped=\"${skipped}\" time=\"${suiteDuration}\">/" \
    -i "${juDir}/${juFile}"

  fi

  # Set returnCode=0: if using flag -status="StatusFile", or if returnCode was either not set or equals 5
  if [[ -f "$statusFile" || -z "$returnCode" || "$returnCode" == 5 ]] ; then
    echo "+++ sh2ju re-setting return code: [${returnCode}] => [0]"
    returnCode=0
  else
    echo -e "+++ sh2ju return code: ${returnCode}\n"
  fi

  set -e # (aka as set -o errexit) to fail script on error
  return ${returnCode}

}
