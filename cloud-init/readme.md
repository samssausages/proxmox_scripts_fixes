Cloud init:

## Docker.yaml
- Installs Docker
- Sets some reasonable defaults
  
## Docker_graylog.yaml

- Installs Docker
- Sets some reasonable defaults
- Configures Remote Logging for Docker to Graylog using GELF
- Configures rsyslog with journald and forwards to Graylog server using rsyslog

Also available without graylog.

Note:
Graylog integration needs logrotate added, so keep in mind that logs may grow large with current config.
I'm testing a new build right now that moves all the logs to memory only and limits to 50MB log size.  (this is for if you have an external syslog server configured)
I'm also testing other methods of sending the logs to Graylog.  So I may change away from rsyslog.
New version expected in about 2 weeks.
