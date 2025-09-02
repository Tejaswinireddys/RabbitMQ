# RabbitMQ Security Checklist

## 🔒 Pre-Deployment Security Checklist

### 1. Password Security
- [ ] All hardcoded passwords have been removed from base configuration
- [ ] Environment-specific files contain strong, unique passwords
- [ ] Passwords meet complexity requirements (12+ characters, mixed case, numbers, symbols)
- [ ] Passwords are stored securely and not committed to version control
- [ ] Default passwords have been changed

### 2. SSL/TLS Configuration
- [ ] SSL/TLS is enabled for all environments
- [ ] Valid SSL certificates are configured for production
- [ ] Certificate paths are correctly specified in environment files
- [ ] SSL verification is enabled (`verify_peer`)
- [ ] Strong cipher suites are configured
- [ ] TLS 1.2 and 1.3 are enabled

### 3. Network Security
- [ ] Firewall rules are properly configured
- [ ] Only necessary ports are open (5672, 15672, 25672, 4369)
- [ ] Network segmentation is implemented
- [ ] Load balancer is configured with SSL termination
- [ ] VPN or private network access is required for management

### 4. User Access Control
- [ ] Default guest user is disabled
- [ ] Admin users have minimal required permissions
- [ ] Service accounts have restricted permissions
- [ ] User roles are properly defined
- [ ] Access is logged and monitored

### 5. Cluster Security
- [ ] Erlang cookie is secure and unique
- [ ] Cluster nodes communicate over secure network
- [ ] Node authentication is properly configured
- [ ] Cluster formation is secured

## 🚀 Deployment Security Checklist

### 1. Installation Security
- [ ] Scripts are run with proper user permissions
- [ ] Configuration files have correct ownership (rabbitmq:rabbitmq)
- [ ] Configuration files have appropriate permissions (644)
- [ ] SSL certificates have correct permissions (600)

### 2. Service Security
- [ ] RabbitMQ service runs as non-root user
- [ ] Service is configured to start automatically
- [ ] Service logs are properly configured
- [ ] Service monitoring is enabled

### 3. Data Security
- [ ] Data directories have correct permissions
- [ ] Backup encryption is configured
- [ ] Data retention policies are defined
- [ ] Audit logging is enabled

## 🔍 Post-Deployment Security Checklist

### 1. Verification
- [ ] SSL connections are working correctly
- [ ] Management interface is accessible only to authorized users
- [ ] Cluster status shows all nodes as healthy
- [ ] No security warnings in logs

### 2. Monitoring
- [ ] Security events are logged
- [ ] Failed login attempts are monitored
- [ ] Unusual access patterns are detected
- [ ] Security alerts are configured

### 3. Maintenance
- [ ] Regular security updates are scheduled
- [ ] SSL certificates are renewed before expiration
- [ ] Security audits are performed regularly
- [ ] Backup integrity is verified

## 🛡️ Security Best Practices

### 1. Password Management
```bash
# Generate secure passwords
openssl rand -base64 32

# Use password hashing in definitions.json
# Never store plain text passwords
```

### 2. SSL Certificate Management
```bash
# Verify certificate validity
openssl x509 -in server_certificate.pem -text -noout

# Check certificate expiration
openssl x509 -in server_certificate.pem -noout -dates
```

### 3. Access Control
```bash
# Review user permissions
rabbitmqctl list_users
rabbitmqctl list_user_permissions username

# Restrict access to specific vhosts
rabbitmqctl set_permissions -p /vhost username ".*" ".*" ".*"
```

### 4. Network Security
```bash
# Verify firewall configuration
firewall-cmd --list-ports

# Check open ports
netstat -tlnp | grep :5672
```

## 🚨 Security Incident Response

### 1. Immediate Actions
- [ ] Isolate affected nodes
- [ ] Change all passwords
- [ ] Revoke compromised certificates
- [ ] Review access logs

### 2. Investigation
- [ ] Analyze security logs
- [ ] Identify attack vector
- [ ] Assess data compromise
- [ ] Document incident

### 3. Recovery
- [ ] Restore from secure backup
- [ ] Implement additional security measures
- [ ] Update incident response procedures
- [ ] Conduct post-incident review

## 📚 Additional Resources

- [RabbitMQ Security Guide](https://www.rabbitmq.com/security.html)
- [OWASP Security Guidelines](https://owasp.org/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [CIS Benchmarks](https://www.cisecurity.org/benchmarks/)

## 📞 Security Support

For security-related issues:
- Contact the security team immediately
- Do not post security issues in public channels
- Follow incident response procedures
- Document all actions taken
