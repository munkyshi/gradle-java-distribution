#!/bin/bash
#
# Copyright 2015 Palantir Technologies
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# <http://www.apache.org/licenses/LICENSE-2.0>
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

is_process_active() {
   local PID=$1
   ps $PID > /dev/null;
   echo $?
}

# Everything in this script is relative to the base directory of an SLSv2 distribution
pushd "`dirname \"$0\"`/../.." > /dev/null

# Select launcher binary for this OS
case "`uname`" in
  Linux*)
    LAUNCHER_CMD=service/bin/linux-amd64/go-java-launcher
    ;;
  Darwin*)
    LAUNCHER_CMD=service/bin/darwin-amd64/go-java-launcher
    ;;
  *)
    echo "Unsupported operating system: $(uname)"; exit 1
esac

ACTION=$1
SERVICE="@serviceName@"
PIDFILE="var/run/$SERVICE.pid"
STATIC_LAUNCHER_CONFIG="service/bin/launcher-static.yml"
CUSTOM_LAUNCHER_CONFIG="var/conf/launcher-custom.yml"
STATIC_LAUNCHER_CHECK_CONFIG="service/bin/launcher-check.yml"

case $ACTION in
start)
    service/bin/init.sh status > /dev/null 2>&1
    if [[ $? == 0 ]]; then
        echo "Process is already running"
        exit 1
    fi
    printf "%-50s" "Running '$SERVICE'..."

    # ensure log and pid directories exist
    mkdir -p "var/log"
    mkdir -p "var/run"
    PID=$($LAUNCHER_CMD $STATIC_LAUNCHER_CONFIG $CUSTOM_LAUNCHER_CONFIG > var/log/$SERVICE-startup.log 2>&1 & echo $!)
    sleep 1
    if [ $(is_process_active $PID) -eq 0 ]; then
        echo $PID > $PIDFILE
        printf "%s\n" "Started ($PID)"
        exit 0
    else
        printf "%s\n" "Failed"
        exit 1
    fi
;;
status)
    printf "%-50s" "Checking '$SERVICE'..."
    if [ -f $PIDFILE ]; then
        PID=$(cat $PIDFILE)
        if [[ $(is_process_active $PID) -eq 0 ]]; then
            ps -o command $PID | grep -q "$SERVICE"
            if [[ $? == 0 ]]; then
                printf "%s\n" "Running ($PID)"
                exit 0
            fi
        fi
        printf "%s\n" "Process dead but pidfile exists"
        exit 1
    else
        printf "%s\n" "Service not running"
        exit 3
    fi
;;
stop)
    printf "%-50s" "Stopping '$SERVICE'..."
    service/bin/init.sh status > /dev/null 2>&1
    if [[ $? == 0 ]]; then
        PID=$(cat $PIDFILE)
        kill $PID
        COUNTER=0
        while [ $(is_process_active $PID) -eq "0" -a "$COUNTER" -lt "240" ]; do
            sleep 1
            let COUNTER=COUNTER+1
            if [ $((COUNTER%5)) == 0 ]; then
                if [ "$COUNTER" -eq "5" ]; then
                    printf "\n" # first time get a new line to get off Stopping printf
                fi
                printf "%s\n" "Waiting for '$SERVICE' ($PID) to stop"
            fi
        done
        if [[ $(is_process_active $PID) -eq "0" ]]; then
            printf "%s\n" "Failed"
            exit 1
        else
            rm -f $PIDFILE
            printf "%s\n" "Stopped ($PID)"
            exit 0
        fi
    else
        rm -f $PIDFILE
        printf "%s\n" "Service not running"
        exit 0
    fi
;;
console)
    service/bin/init.sh status > /dev/null 2>&1
    if [[ $? == 0 ]]; then
        echo "Process is already running"
        exit 1
    fi
    trap "service/bin/init.sh stop &> /dev/null" SIGTERM EXIT
    mkdir -p "$(dirname $PIDFILE)"

    $LAUNCHER_CMD $STATIC_LAUNCHER_CONFIG $CUSTOM_LAUNCHER_CONFIG &
    echo $! > $PIDFILE
    wait
;;
restart)
    service/bin/init.sh stop
    service/bin/init.sh start
;;
check)
    printf "%-50s" "Checking health of '$SERVICE'..."
    $LAUNCHER_CMD $STATIC_LAUNCHER_CHECK_CONFIG > var/log/$SERVICE-check.log 2>&1
    RESULT=$?
    if [ $RESULT -eq 0 ]; then
        printf "%s\n" "Healthy"
        exit 0
    else
        printf "%s\n" "Unhealthy"
        exit $RESULT
    fi
;;
*)
    echo "Usage: $0 {status|start|stop|console|restart|check}"
    exit 1
esac
