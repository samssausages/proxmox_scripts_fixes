Cloud init:

## Docker.yml
- Installs Docker
- Sets some reasonable defaults
  
## Docker_graylog.yml

- Installs Docker
- Sets some reasonable defaults
- Configures Remote Logging for Docker to Graylog using GELF
- Configures VM with rsyslog and forwards to Graylog server using rsyslog
- Make sure you set your syslog IP address in the .yml file, or it will use the default IP to try and forward to.


Note:
Graylog integration needs logrotate added, so keep in mind that logs may grow large with current config.
I'm testing a new build right now that moves all the logs to memory only and limits to 50MB log size.  (this is for if you have an external syslog server configured)
I'm also testing other methods of sending the logs to Graylog.  So I may change away from rsyslog.
New version expected in about 2 weeks.
