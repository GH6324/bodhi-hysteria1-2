function handle_stop
    if $hysteria2
        rm -f userlist server.yaml knck stop
    else
        rm -f userlist server.json knck stop
    end
    echo
    logger 2 "@bodhi.handle_stop -> Stopped"
    exit 0
end
