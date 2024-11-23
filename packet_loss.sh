#!/bin/bash
__version="1.6.0 2021-12-18"
#
# Copyright (c) 2020,2021: Jacob.Lundqvist@gmail.com
# License: MIT
#
# Part of https://github.com/jaclu/helpfull_scripts
#
#  Version: $__version
#       Added handling of different types of ping with various
#       locations of percentage loss in output.
#   1.5.3 2021-11-14
#       Added check if ping is the busybox version,
#       without timeout param and deals with it.
#       Removed timeout calculations, didn't make sense.
#   1.5.2 2021-11-14
#       Ensure host is responding when starting.
#       Shortened output lines, so they can run in a 28 col terminal.
#       Corrected printout after Ctrl-C to point out what is included.
#       Changed min allowed count into 1.
#   1.5.1 2021-11-11
#       Uses timeout of ping_count * 1.5 rounded for ping
#       Does requested amount of pings again.
#   1.5.0 2021-11-10
#       Added 2nd param host.
#       increased min ping_count since low numbers tende
#       to give false negatives.
#       Does one more ping than ping count, since first ping is
#       sent at time 0, to line up timestamps with ping count
#       I.E 5 will display status every 5s and so on.
#       reduced output to fit a smaller width
#   1.4.1 2021-10-02
#       Switched shell from bash to /bin/sh
#       now prints total ping count and losses upon Ctrl-C termination
#       Fixed emacs ruined indents again, need to check my emacs config...
#   1.4.0  2020-08-11
#       Added support for multi route testing
#
#  Displays packet loss over time, see below for more usage hints
#

#
#  number of pings in each check
#  ie how often you will get updated
#  can be overridden by param1
#
ping_count=60

#
# what to ping (can be overriden by param2)
#
hosts="1.1.1.1 1.0.0.1"

# Interfaces to test connectivity
# Add multiple interfaces separated by spaces (e.g., "eth0 eth0.52 eth0.55")
interfaces="eth0 eth0.42 eth0.14 eth0.69"


#==========================================
#
#  End of user configuration part
#
#==========================================


echo "$(basename "$0") version: $__version"


#
#  Override ping_count with param 1
#
if [ $# -gt 2 ] ; then
    echo "ERROR: Only params supported - pingcount and host."
    exit 1
fi




if [ -n  "$1" ] ; then
    ping_count="$1"
    case "$ping_count" in

        (*[!0123456789]*)
            echo "ERROR param 1 not a valid integer value!"
            exit 1
            ;;

    esac
    if [ "$ping_count" -lt 1 ]; then
        echo "WARNING: $ping_count is not a meaningfull value, changed to 1  ***"
        ping_count=1
    fi
fi


#
#   Override default host with param 2
#
if [ -n "$2" ]; then
    host="$2"
fi



#
#
#  2021-12-18 How can such a common and basic command as ping have different
#  paramas on MacOS & linux?? I could have done this checking uname and let
#  OS decide, but if there are other systems with other pings,
#  lets just do it the hard way.
#

# Argh, even the position for % packet loss is not constant...
packet_loss_param_no="7"

# triggering an eror printing valid params...
timeout_help="$(ping -h 2> /dev/stdout| grep timeout)"

if [ "${timeout_help#*-t}" != "$timeout_help" ]; then
    timeout_flag="t"
elif [ "${timeout_help#*-W}" != "$timeout_help" ]; then
    timeout_flag="W"
    packet_loss_param_no="6"
else
    timeout_flag=""
fi

if [ -n "$timeout_flag" ]; then
    ping_tst_cmd="ping -$timeout_flag 1"
    ping_cmd="ping -$timeout_flag $ping_count"
else
    ping_tst_cmd="ping"
    ping_cmd="ping"
    echo
    echo "WARNING: This ping does not support timeouts, so when a host is not responding"
    echo "         an extra 10 seconds will be spent timing out"
    echo
fi
# to avoid redundant typing common params are given once here
ping_cmd="$ping_cmd -c $ping_count $host"


#
#  Check if host is initially responding.
#
for current_host in $hosts; do
    if ! $ping_tst_cmd -c 1 "$current_host" > /dev/null; then
        echo
        echo "WARNING: Host $current_host is not responding!"
        echo
    fi
done


#
#  Explaining task at hand
#
echo "This will ping once per second and report packet loss with"
printf '%s every %s packets' "$host" "$ping_count"

if [ -n "$timeout_flag" ]; then
    echo ", timing out after $ping_count seconds."
else
    echo "."
fi
echo

trap '
    echo
    echo "Stats up to last printout:"
    if [ $global_sent_packets -gt 0 ]; then
        total_percentage=$(echo "$global_dropped_packets $global_sent_packets" | awk "{print (\$1 / \$2) * 100}")
    else
        total_percentage="N/A"
    fi

    if [ $global_sent_packets -gt 0 ]; then
        global_avg_rtt=$(echo "$global_total_rtt $global_sent_packets" | awk "{printf \"%.2f\", \$1 / \$2}")
    else
        global_avg_rtt="N/A"
    fi

    # Calculate total average jitter across all interfaces
    total_avg_jitter=0
    jitter_count=0
    all_nan=true
    for interface in $interfaces; do
        if [ "${avg_jitter[$interface]}" != "NaN" ] && [ ${total_sent_packets[$interface]} -gt 0 ]; then
            total_avg_jitter=$(echo "$total_avg_jitter ${avg_jitter[$interface]}" | awk "{print \$1 + \$2}")
            jitter_count=$((jitter_count + 1))
            all_nan=false
        fi
    done
    if [ $jitter_count -gt 0 ]; then
        total_avg_jitter=$(echo "$total_avg_jitter $jitter_count" | awk "{printf \"%.2f\", \$1 / \$2}")
    elif [ "$all_nan" = true ]; then
        total_avg_jitter="N/A"
    else
        total_avg_jitter=0
    fi

    echo "  Total Pings: $global_sent_packets, Total Packet Loss: $global_dropped_packets ($total_percentage%)"
    echo "  Total Average Jitter: $total_avg_jitter"
    echo "  Total Average Time: $global_avg_rtt"
    echo
    printf "%-9s %-11s %6s %8s %9s %11s %12s %10s %11s\n" "Interface" "Host" "Sent" "Dropped" "Loss (%)" "Avg Jitter" "Time" "Avg Time" "Max Time"
    for interface in $interfaces; do
        for current_host in $hosts; do
            loss_percentage=$(echo "${total_dropped_packets[$interface]} ${total_sent_packets[$interface]}" | \
                              awk "{if (\$2 > 0) print (\$1 / \$2) * 100; else print 0}")
            
            time_display="${last_packet_time[$interface]}"
            avg_time_display="${avg_rtt[$interface]}"
            max_time_display="${max_rtt[$interface]}"
            
            if [ "${total_dropped_packets[$interface]}" -eq "${total_sent_packets[$interface]}" ]; then
                # Set N/A for dropped packets
                time_display="N/A"
                avg_time_display="N/A"
                max_time_display="N/A"
            fi

            if [ "${avg_jitter[$interface]}" == "NaN" ]; then
                avg_jitter[$interface]="N/A"
            fi

            printf "%-9s %-11s %6d %8d %8.1f%% %11s %12s %10s %10s\n" \
                   "$interface" "$current_host" "${total_sent_packets[$interface]}" "${total_dropped_packets[$interface]}" \
                   "$loss_percentage" "${avg_jitter[$interface]}" "$time_display" "$avg_time_display" "$max_time_display"
        done
    done
    trap - INT # Restore default INT handler
    kill -s INT "$$"
' INT

#==========================================
#
#  Main loop for multiple hosts
#
#==========================================

# Initialize packet loss counters, jitter, and time metrics for each interface
declare -A total_sent_packets
declare -A total_dropped_packets
declare -A previous_output
declare -A jitter
declare -A avg_jitter
declare -A prev_rtt
declare -A last_packet_time
declare -A total_rtt
declare -A avg_rtt
declare -A max_rtt

for interface in $interfaces; do
    total_sent_packets[$interface]=0
    total_dropped_packets[$interface]=0
    previous_output[$interface]=""
    jitter[$interface]=0
    avg_jitter[$interface]=0
    prev_rtt[$interface]=""
    last_packet_time[$interface]="N/A"
    total_rtt[$interface]=0
    avg_rtt[$interface]=0
    max_rtt[$interface]=0
done

# Initialize global counters
global_sent_packets=0
global_dropped_packets=0
global_total_rtt=0
global_avg_rtt=0

# Infinite loop to alternate between hosts
while true; do
    for current_host in $hosts; do
        output=""
        pids=()

        for interface in $interfaces; do
            # Set the ping command for the current interface and host
            ping_cmd="ping -I $interface -c $ping_count $current_host"

            # Run the ping command in the background and store the process ID
            $ping_cmd > /tmp/ping_${interface}_${current_host//./_}.log &
            pids+=($!)
        done

        # Wait for all pings to complete
        for pid in "${pids[@]}"; do
            wait $pid
        done

        # Process the output for each interface
        for interface in $interfaces; do
            log_file="/tmp/ping_${interface}_${current_host//./_}.log"
            ping_output=$(grep -i loss "$log_file")
            rtt_values=$(grep "time=" "$log_file" | awk -F'time=' '{print $2}' | awk '{print $1}')

            # Skip processing if log is empty or invalid
            if [ -z "$ping_output" ]; then
                echo "Warning: No valid output for $interface on $current_host."
                continue
            fi

            # Extract packet statistics
            this_time_sent=$(echo "$ping_output" | awk -F, '{print $1}' | grep -o '[0-9]*')
            this_time_received=$(echo "$ping_output" | awk -F, '{print $2}' | grep -o '[0-9]*')
            this_time_packet_loss=$((this_time_sent - this_time_received))

            # Update interface-level and global counters
            total_sent_packets[$interface]=$((total_sent_packets[$interface] + this_time_sent))
            total_dropped_packets[$interface]=$((total_dropped_packets[$interface] + this_time_packet_loss))
            global_sent_packets=$((global_sent_packets + this_time_sent))
            global_dropped_packets=$((global_dropped_packets + this_time_packet_loss))

            # Calculate cumulative packet loss percentage
            if [ ${total_sent_packets[$interface]} -gt 0 ]; then
                cumulative_loss=$(awk -v dropped="${total_dropped_packets[$interface]}" -v sent="${total_sent_packets[$interface]}" 'BEGIN { print 100 * (dropped / sent) }')
            else
                cumulative_loss=0
            fi

            # Calculate time metrics
            if [ -n "$rtt_values" ]; then
                last_packet_time[$interface]=$(echo "$rtt_values" | tail -n 1)
                for rtt in $rtt_values; do
                    total_rtt[$interface]=$(echo "${total_rtt[$interface]} $rtt" | awk '{print $1 + $2}')
                    global_total_rtt=$(echo "$global_total_rtt $rtt" | awk '{print $1 + $2}')
                    if (( $(echo "$rtt > ${max_rtt[$interface]}" | bc -l) )); then
                        max_rtt[$interface]=$rtt
                    fi
                done
                avg_rtt[$interface]=$(echo "${total_rtt[$interface]} ${total_sent_packets[$interface]}" | awk '{printf "%.1f", $1 / $2}')
            else
                last_packet_time[$interface]="N/A"
                max_rtt[$interface]="N/A"
                avg_rtt[$interface]="N/A"
            fi

            # Calculate jitter for this run
            total_jitter=0
            jitter_count=0

            for rtt in $rtt_values; do
                if [ -n "${prev_rtt[$interface]}" ]; then
                    jitter_value=$(awk -v curr="$rtt" -v prev="${prev_rtt[$interface]}" 'BEGIN { print (curr > prev ? curr - prev : prev - curr) }')
                    total_jitter=$(awk -v t="$total_jitter" -v j="$jitter_value" 'BEGIN { print t + j }')
                    jitter_count=$((jitter_count + 1))
                fi
                prev_rtt[$interface]="$rtt" # Update the last RTT for this interface
            done

            if [ $jitter_count -gt 0 ]; then
                jitter[$interface]=$(awk -v total="$total_jitter" -v count="$jitter_count" 'BEGIN { printf "%.1f", total / count }')
            else
                if [ "$this_time_packet_loss" -eq "$this_time_sent" ]; then
                    jitter[$interface]="NaN" # Set jitter to NaN if all packets are dropped
                else
                    jitter[$interface]=0.0
                fi
            fi

            # Calculate cumulative average jitter
            avg_jitter[$interface]=$(awk -v curr_avg="${avg_jitter[$interface]}" -v curr_jitter="${jitter[$interface]}" 'BEGIN { print (curr_avg + curr_jitter) / 2 }')

            # Prepare current output for this interface
            current_output=$(printf "%-9s %-10s dropped:%-3d (%3.0f%%)   jitter:%-6s avg_jitter:%-6.1f  time:%-6s avg_time:%-6s max_time:%-6s %s\n" \
                 "$interface" "$current_host" "${total_dropped_packets[$interface]}" "$cumulative_loss" \
                 "${jitter[$interface]}" "${avg_jitter[$interface]}" "${last_packet_time[$interface]}" \
                 "${avg_rtt[$interface]}" "${max_rtt[$interface]}" "$(date +'%I:%M:%S%p')")

            # Only print if the output has changed for this interface
            if [ "$current_output" != "${previous_output[$interface]}" ]; then
                output+="${current_output}\n"
                previous_output[$interface]=$current_output
            fi
        done

        # Print consolidated output if there's any change
        if [ -n "$output" ]; then
            echo -e "$output"
            echo   # Add an extra blank line between updates for readability
        fi
    done
done
