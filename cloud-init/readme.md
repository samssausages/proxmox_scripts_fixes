Cloud init:

## Docker.yml
- Installs Docker
- Sets some reasonable defaults
  
## Docker_graylog.yml

- Installs Docker
- Sets some reasonable defaults
- Configures Remote Logging for Docker to Graylog using GELF (DOCKER MUST BE ABLE OT ACCESS SERVER OR ERROR WILL BE PRODUCED)
- Configures VM with rsyslog and forwards to Graylog server using rsyslog
- Make sure you set your syslog IP address in the .yml file, or it will use the default IP to try and forward to.
- Installs & configrues logrotate

Note: you must add the ip to your syslog and gelf server in the graylog file.
