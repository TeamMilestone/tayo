# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
Tayo is a Ruby gem that simplifies Rails app deployment to home servers using GitHub Container Registry and Cloudflare.

## Common Development Commands

### Testing
```bash
# Run all tests
rake test

# Run specific test file
ruby -Ilib:test test/dockerfile_modifier_test.rb
```

### Building and Installing
```bash
# Build gem
rake build

# Install locally
rake install

# Release to RubyGems.org
rake release
```

## Architecture

### Core Structure
- `lib/tayo/cli.rb` - Thor-based CLI entry point
- `lib/tayo/commands/` - Command modules:
  - `init.rb` - Rails project initialization with Docker setup
  - `gh.rb` - GitHub repository and Container Registry configuration
  - `cf.rb` - Cloudflare DNS configuration
- `lib/tayo/dockerfile_modifier.rb` - Handles bootsnap removal from Dockerfiles

### Key Patterns
1. **Command Structure**: Each command is a separate module under `Commands`
2. **Error Handling**: Use colorized Korean messages for user-friendly output
3. **Security**: Store sensitive tokens with 600 permissions, use macOS Keychain for Cloudflare tokens
4. **Git Integration**: Auto-commit after each major step with descriptive messages
5. **User Interaction**: Use TTY::Prompt for interactive configuration

### Workflow
The typical usage flow:
1. `tayo init` - Sets up Rails project with Docker
2. `tayo gh` - Configures GitHub repository and Container Registry
3. `tayo cf` - Sets up Cloudflare DNS
4. `bin/kamal setup` - Deploys the application

### Testing Approach
- Uses Minitest framework
- Tests focus on unit testing individual components
- DockerfileModifier has comprehensive test coverage