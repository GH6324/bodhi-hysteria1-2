function push
    while true
        sleep $argv[1]
        curl -sL "$upstream_api/api/v1/server/UniProxy/user?node_id=$nodeid&node_type=hysteria&token=$psk" -o userlist
        set raw_conf_md5_check (curl -sL "$upstream_api/api/v1/server/UniProxy/config?node_id=$nodeid&node_type=hysteria&token=$psk" | md5sum | string split ' ')[1]
        # Create UserTable
        set users (yq '.users[].id' userlist)
        # Map id <=> uuid <=> base64_authstr
        for user in $users
            set uuid[$user] (yq ".users[]|select(.id == $user)|.uuid" userlist)
            set basestr[$user] (echo -n "$uuid[$user]" | base64)
        end
        # fetch data from api
        if $hysteria2
            set raw_statis (curl -sL "http://127.0.0.1:$api_port/traffic")
            if test "$raw_statis" = "{}"
                if test "$bodhi_verbose" = debug
                    logger 3 "@bodhi.push CONT -> No usage, skip reporting"
                end
                if test "$raw_conf_md5_check" != "$argv[3]"
                    set raw_conf (curl -sL "$upstream_api/api/v1/server/UniProxy/config?node_id=$nodeid&node_type=hysteria&token=$psk")
                    if string match -q '*obfs*' -- $raw_conf
                        logger 4 "@bodhi.push WARN -> New config from panel arrived, re-init server"
                        break
                    end
                end
            else
                # Loop to collect data High-Passly
                # Stay tuned
            end
        else
            set raw_statis (curl -sL "http://127.0.0.1:$api_port/metrics" | string collect)
            if test -z $raw_statis
                if test "$bodhi_verbose" = debug
                    logger 3 "@bodhi.push CONT -> No usage, skip reporting"
                end
                if test "$raw_conf_md5_check" != "$argv[3]"
                    set raw_conf (curl -sL "$upstream_api/api/v1/server/UniProxy/config?node_id=$nodeid&node_type=hysteria&token=$psk")
                    if string match -q '*obfs*' -- $raw_conf
                        logger 4 "@bodhi.push WARN -> New config from panel arrived, re-init server"
                        break
                    end
                end
            else
                # Loop to collect data High-Passly
                for line_stat in (curl -sL "http://127.0.0.1:$api_port/metrics")
                    if string match -q '*'\#'*' -- $line_stat; or string match -q '*active_conn*' -- $line_stat
                    else
                        set line_id (contains --index -- (string match -r 'auth="(.+?)"' $line_stat)[2] $basestr)
                        set usage (math (string split ' ' -- $line_stat)[2])
                        if string match -rq uplink -- $line_stat
                            if test -z $last_upload[$line_id]
                                set last_upload[$line_id] 0
                            end
                            set upload[$line_id] (math $usage - $last_upload[$line_id])
                            set last_upload[$line_id] $usage
                        else
                            if test -z $last_download[$line_id]
                                set last_download[$line_id] 0
                            end
                            set download[$line_id] (math $usage - $last_download[$line_id])
                            set last_download[$line_id] $usage
                        end
                    end
                end
            end
            # compose json data
            set return_data '{}'
            for user in $users
                if test -z $upload[$user]; and test -z $download[$user]
                else
                    if test $upload[$user] = 0; and test $download[$user] = 0
                    else
                        set return_data (echo -n "$return_data" | yq -o=json ".$user = [$upload[$user], $download[$user]]")
                    end
                end
            end
            if test "$bodhi_verbose" = debug
                logger 3 "@bodhi.push CONT -> Ready to push with following data"
                logger 3 "$return_data"
            end
            # Report data to panel
            if test "$return_data" = '{}'
                if test "$bodhi_verbose" = debug
                    logger 3 "@bodhi.push CONT -> No usage, skip reporting"
                end
            else
                set clength (echo -n "$return_data" | wc -c)
                curl -sL -X POST -H "Content-Type: application/json" -H "Content-Length: $clength" -d "$return_data" "$upstream_api/api/v1/server/UniProxy/push?node_id=$nodeid&node_type=hysteria&token=$psk" | yq
            end
            if test "$raw_conf_md5_check" != "$argv[3]"
                set raw_conf (curl -sL "$upstream_api/api/v1/server/UniProxy/config?node_id=$nodeid&node_type=hysteria&token=$psk")
                if string match -q '*obfs*' -- $raw_conf
                    logger 4 "@bodhi.push WARN -> New config from panel arrived, re-init server"
                    break
                end
            end
        end
    end
    kill $argv[2]
    rm -f userlist server.json knck stop
    chamber
end
