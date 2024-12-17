# KeyHippo

Add powerful, secure API key authentication to your Supabase project.

<!-- markdownlint-disable-next-line -->
<div align="center">

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/integrated-reasoning/KeyHippo/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE-MIT)
[![Super-Linter](https://github.com/integrated-reasoning/KeyHippo/actions/workflows/lint.yml/badge.svg)](https://github.com/marketplace/actions/super-linter)

</div>

## What is KeyHippo?

KeyHippo extends Supabase with industrial-strength API key authentication that works seamlessly with Row Level Security (RLS) and Role-Based Access Control (RBAC).

### Key Features

- **✨ Easy Integration**: Works directly with your existing Supabase setup
- **🔒 Security First**: Zero plaintext storage, high-entropy keys, audit logging
- **🎯 Fine-Grained Control**: Tenant isolation, role-based access, custom claims
- **⚡ High Performance**: Pure SQL implementation, optimized queries
- **🛠️ Developer Friendly**: Clear APIs, comprehensive docs, real-world patterns

## Quick Start

### Prerequisites

- PostgreSQL 14+
- Supabase project (or compatible PostgreSQL setup)

### Installation

```sql
-- Install required extension
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Install KeyHippo
\i sql/install.sql

-- Initialize
SELECT keyhippo.initialize_keyhippo();
```

### Basic Usage

1. Create an API key:
```sql
SELECT * FROM keyhippo.create_api_key('My First API Key');
```

2. Use in your RLS policies:
```sql
CREATE POLICY "api_access" ON "resources"
    FOR ALL
    USING (
        -- Allow access with valid API key
        (SELECT user_id FROM keyhippo.current_user_context()) IS NOT NULL
    );
```

3. Make API requests:
```bash
curl -X GET 'https://your-project.supabase.co/rest/v1/resources' \
     -H 'x-api-key: your_api_key_here'
```

## Documentation

### Getting Started
- [🚀 QuickStart Guide](docs/guides/quickstart.md) - Basic setup and usage
- [🏢 Enterprise Guide](docs/guides/enterprise_quickstart.md) - Multi-tenant setup

### Implementation Guides
- [🔑 API Key Patterns](docs/guides/api_key_patterns.md) - Common implementation patterns
- [🏠 Multi-Tenant Guide](docs/guides/multi_tenant.md) - Tenant isolation patterns

### Reference
- [📚 API Documentation](docs/api/index.md) - Complete API reference
- [🛡️ Security Guide](docs/api/security/rls_policies.md) - Security best practices

## Development

### Local Setup

```bash
# Clone repository
git clone https://github.com/integrated-reasoning/KeyHippo.git
cd KeyHippo

# Install dependencies
make install

# Run tests
make test

# Run linter
make lint
```

### Contributing

We welcome contributions! Before submitting a PR:

1. Read our [Contributing Guide](CONTRIBUTING.md)
2. Run tests (`make test`)
3. Update documentation as needed
4. Add tests for new features

## Support

- [📝 Issues](https://github.com/integrated-reasoning/KeyHippo/issues) - Bug reports and features
- [🤝 Discussions](https://github.com/integrated-reasoning/KeyHippo/discussions) - Questions and ideas
- [🔒 Security](SECURITY.md) - Vulnerability reporting
- [💼 Enterprise](https://keyhippo.com) - Commercial support

## License

KeyHippo is MIT licensed. See [LICENSE](LICENSE) for details.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=integrated-reasoning/KeyHippo&type=Timeline)](https://star-history.com/#integrated-reasoning/KeyHippo&Timeline)