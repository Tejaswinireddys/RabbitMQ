# RabbitMQ User Credentials Documentation

## User Account Information

### Administrator Account
- **Username**: `admin`
- **Password**: `admin123`
- **Role**: Administrator
- **Permissions**: Full administrative access to all vhosts
- **Tags**: `administrator`

### Management Users

#### User: Teja
- **Username**: `teja`
- **Password**: `Teja@2024`
- **Role**: Management User
- **Permissions**: Full access to default vhost (/)
- **Tags**: `management`
- **Access Level**: Can manage queues, exchanges, bindings, and view cluster information

#### User: Aswini
- **Username**: `aswini`
- **Password**: `Aswini@2024`
- **Role**: Management User
- **Permissions**: Full access to default vhost (/)
- **Tags**: `management`
- **Access Level**: Can manage queues, exchanges, bindings, and view cluster information

## Access Methods

### Management Web Interface
- **URL**: `http://your-server-ip:15672`
- **SSL URL**: `https://your-server-ip:15671` (if SSL configured)
- **Login**: Use any of the above credentials

### Command Line Access
```bash
# List users
sudo rabbitmqctl list_users

# Check user permissions
sudo rabbitmqctl list_permissions

# Test user authentication
sudo rabbitmqctl authenticate_user teja Teja@2024
sudo rabbitmqctl authenticate_user aswini Aswini@2024
```

### Application Connection Strings

#### AMQP Connection (Standard)
```
# For user Teja
amqp://teja:Teja@2024@server-ip:5672/

# For user Aswini
amqp://aswini:Aswini@2024@server-ip:5672/
```

#### AMQP SSL Connection
```
# For user Teja
amqps://teja:Teja@2024@server-ip:5671/

# For user Aswini
amqps://aswini:Aswini@2024@server-ip:5671/
```

## Password Policy

### Current Password Requirements
- Minimum 8 characters
- Must contain uppercase letters
- Must contain special characters
- Must contain numbers

### Password Change Commands
```bash
# Change password for user Teja
sudo rabbitmqctl change_password teja "NewPassword@2024"

# Change password for user Aswini
sudo rabbitmqctl change_password aswini "NewPassword@2024"
```

## User Permissions Matrix

| User | VHost | Configure | Write | Read | Management UI | Monitoring |
|------|-------|-----------|-------|------|---------------|------------|
| admin | / | ✓ | ✓ | ✓ | ✓ | ✓ |
| teja | / | ✓ | ✓ | ✓ | ✓ | ✓ |
| aswini | / | ✓ | ✓ | ✓ | ✓ | ✓ |

## Security Considerations

### Password Security
- All passwords use strong complexity requirements
- Default guest user is disabled for security
- Passwords are hashed using SHA-256 algorithm
- Consider implementing password rotation policy

### Network Security
- Management interface should be restricted to admin networks
- AMQP connections should use SSL in production
- Consider implementing IP whitelisting for sensitive users

### Access Control
- Users have management tags allowing full queue/exchange management
- Monitor user activity through RabbitMQ logs
- Implement least privilege principle for application users

## User Management Commands

### Create Additional Users
```bash
# Create a new user
sudo rabbitmqctl add_user newuser password123

# Set user tags (administrator, monitoring, management, none)
sudo rabbitmqctl set_user_tags newuser management

# Set permissions (vhost, configure, write, read)
sudo rabbitmqctl set_permissions -p / newuser ".*" ".*" ".*"
```

### Remove Users
```bash
# Delete a user
sudo rabbitmqctl delete_user username

# Clear user permissions
sudo rabbitmqctl clear_permissions -p / username
```

### Modify User Permissions
```bash
# Set specific permissions (example: read-only)
sudo rabbitmqctl set_permissions -p / username "" "" ".*"

# Set permissions for specific queues only
sudo rabbitmqctl set_permissions -p / username "queue\\.myapp\\..*" "queue\\.myapp\\..*" "queue\\.myapp\\..*"
```

## Application Integration Examples

### Java/Spring Boot
```properties
# application.properties
spring.rabbitmq.host=your-server-ip
spring.rabbitmq.port=5672
spring.rabbitmq.username=teja
spring.rabbitmq.password=Teja@2024
spring.rabbitmq.virtual-host=/
```

### Python (pika)
```python
import pika

credentials = pika.PlainCredentials('teja', 'Teja@2024')
connection = pika.BlockingConnection(
    pika.ConnectionParameters('your-server-ip', 5672, '/', credentials)
)
```

### Node.js (amqplib)
```javascript
const amqp = require('amqplib');

const connection = await amqp.connect('amqp://teja:Teja@2024@your-server-ip:5672/');
```

### .NET Core
```csharp
var factory = new ConnectionFactory()
{
    HostName = "your-server-ip",
    UserName = "teja",
    Password = "Teja@2024",
    VirtualHost = "/"
};
```

## Monitoring and Auditing

### User Activity Monitoring
```bash
# Check current connections by user
sudo rabbitmqctl list_connections user

# Check user permissions
sudo rabbitmqctl list_user_permissions teja
sudo rabbitmqctl list_user_permissions aswini

# Check which users have access to specific vhost
sudo rabbitmqctl list_permissions -p /
```

### Log Analysis
- User login attempts logged in RabbitMQ logs
- Failed authentication attempts are recorded
- Monitor `/var/log/rabbitmq/rabbit@hostname.log` for user activities

## Backup and Recovery

### User Configuration Backup
```bash
# Export user definitions
sudo rabbitmqctl export_definitions /backup/user-definitions.json

# Import user definitions
sudo rabbitmqctl import_definitions /backup/user-definitions.json
```

### Emergency Access
- Keep admin credentials secure and accessible to authorized personnel only
- Document emergency procedures for password resets
- Maintain offline copy of user credentials in secure location

## Change Management

### Password Rotation Schedule
- Quarterly password changes recommended for production
- Document all password changes
- Notify application teams before password changes

### User Review Process
- Monthly review of active users
- Quarterly audit of user permissions
- Annual review of access requirements

---

**Security Notice**: This document contains sensitive credential information. Store securely and limit access to authorized personnel only.