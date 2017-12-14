#!/bin/bash
# sleeping for 10 seconds to let grafana get up and running
if [ -f /etc/grafana/skip-export-datasources-and-dashboards ]; then
    exit 0
fi
sleep 10 && wizzy export datasources && wizzy export dashboards
