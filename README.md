# KeyHippo

Industrial-strength API key auth for modern Postgres applications.

<!-- markdownlint-disable-next-line -->
<div align="center">

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/integrated-reasoning/KeyHippo/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE-MIT)
[![Super-Linter](https://github.com/integrated-reasoning/KeyHippo/actions/workflows/lint.yml/badge.svg)](https://github.com/marketplace/actions/super-linter)

</div>

## What is KeyHippo?

KeyHippo adds production-ready API key authentication to Supabase that works seamlessly with Row Level Security (RLS) and Role-Based Access Control (RBAC).

### Key Features

- **✨ Instant Setup**: 2-minute setup, immediate value
- **🔒 Production Ready**: Built-in audit logs, key rotation, tenant isolation
- **🎯 Scale With You**: From prototype to millions of users
- **⚡ High Performance**: Pure SQL, no extra services
- **🛠️ Developer Experience**: Clear APIs, real examples, zero friction

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

## Performance

Single-core P99 benchmarks on AMD Threadripper 3960X:

| Operation | P99 Time (ms) | Ops/Sec |
|-----------|---------------|----------|
| API key verification | 0.065 | 15,385 |
| RBAC authorization | 0.036 | 27,778 |
| Role assignment | 0.016 | 62,500 |

[📊 View full benchmarks](docs/performance.md)

## Documentation

### Getting Started
- [🚀 5-Minute Quickstart](docs/guides/quickstart.md) - From zero to working API keys
- [🏢 Multi-Tenant Setup](docs/guides/multi_tenant_quickstart.md) - Scale with your user base

### Implementation Guides
- [🔑 API Key Patterns](docs/guides/api_key_patterns.md) - Real-world implementation patterns
- [🏠 Tenant Isolation](docs/guides/multi_tenant.md) - Clean multi-tenant architecture

### Reference
- [📚 API Documentation](docs/api/index.md) - Complete API reference
- [🛡️ Security Guide](docs/api/security/rls_policies.md) - Production security

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
- [💼 Pro Support](https://keyhippo.com) - Priority support & custom features

## License

KeyHippo is MIT licensed. See [LICENSE](LICENSE) for details.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=integrated-reasoning/KeyHippo&type=Timeline)](https://star-history.com/#integrated-reasoning/KeyHippo&Timeline)