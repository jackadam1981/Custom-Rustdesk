#!/bin/bash

# 项目健康检查脚本
# 用于检查Custom Rustdesk构建项目的整体健康状态

set -e

echo "🔍 开始项目健康检查..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查函数
check_file_permissions() {
    echo "📁 检查文件权限..."

    local issues=0

    # 检查shell脚本权限
    for script in $(find . -name "*.sh" -type f); do
        if [[ ! -x "$script" ]]; then
            echo -e "${YELLOW}⚠️  $script 缺少执行权限${NC}"
            ((issues++))
        fi
    done

    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}✅ 所有脚本都有正确的执行权限${NC}"
    else
        echo -e "${YELLOW}⚠️  发现 $issues 个权限问题${NC}"
    fi
}

check_dependencies() {
    echo "🔧 检查依赖项..."

    local missing_deps=0

    # 检查必需的命令
    for cmd in jq gh curl openssl bc; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}❌ 缺少依赖: $cmd${NC}"
            ((missing_deps++))
        else
            echo -e "${GREEN}✅ $cmd 已安装${NC}"
        fi
    done

    if [[ $missing_deps -gt 0 ]]; then
        echo -e "${RED}❌ 缺少 $missing_deps 个必需依赖${NC}"
        return 1
    fi
}

check_environment() {
    echo "🌍 检查环境配置..."

    # 检查.env文件
    if [[ ! -f ".env" ]]; then
        echo -e "${RED}❌ .env 文件不存在${NC}"
        return 1
    fi

    # 检查必需的环境变量
    if ! grep -q "GITHUB_TOKEN" .env; then
        echo -e "${RED}❌ .env 文件中缺少 GITHUB_TOKEN${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ 环境配置文件正常${NC}"
}

check_gitignore() {
    echo "🚫 检查.gitignore配置..."

    if [[ ! -f ".gitignore" ]]; then
        echo -e "${RED}❌ .gitignore 文件不存在${NC}"
        return 1
    fi

    # 检查敏感文件是否被忽略
    local sensitive_patterns=(".env" "*.log" "*.tmp" "*.key" "*.pem")
    local missing_patterns=0

    for pattern in "${sensitive_patterns[@]}"; do
        if ! grep -q "$pattern" .gitignore; then
            echo -e "${YELLOW}⚠️  .gitignore 缺少模式: $pattern${NC}"
            ((missing_patterns++))
        fi
    done

    if [[ $missing_patterns -eq 0 ]]; then
        echo -e "${GREEN}✅ .gitignore 配置完整${NC}"
    fi
}

check_workflow_syntax() {
    echo "🔄 检查工作流语法..."

    local yaml_files=$(find .github/workflows -name "*.yml" -o -name "*.yaml")
    local syntax_errors=0

    for yaml_file in $yaml_files; do
        if ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
            echo -e "${RED}❌ $yaml_file 语法错误${NC}"
            ((syntax_errors++))
        else
            echo -e "${GREEN}✅ $yaml_file 语法正确${NC}"
        fi
    done

    if [[ $syntax_errors -gt 0 ]]; then
        echo -e "${RED}❌ 发现 $syntax_errors 个YAML语法错误${NC}"
        return 1
    fi
}

check_script_syntax() {
    echo "🐚 检查脚本语法..."

    local bash_files=$(find . -name "*.sh" -type f)
    local syntax_errors=0

    for bash_file in $bash_files; do
        if ! bash -n "$bash_file" 2>/dev/null; then
            echo -e "${RED}❌ $bash_file 语法错误${NC}"
            ((syntax_errors++))
        fi
    done

    if [[ $syntax_errors -eq 0 ]]; then
        echo -e "${GREEN}✅ 所有脚本语法正确${NC}"
    else
        echo -e "${RED}❌ 发现 $syntax_errors 个脚本语法错误${NC}"
        return 1
    fi
}

check_security() {
    echo "🔒 检查安全配置..."

    local security_issues=0

    # 检查是否有硬编码的敏感信息
    if grep -r "password\|token\|secret\|key" --include="*.sh" --include="*.yml" --include="*.md" . | grep -v "secrets\." | grep -v "GITHUB_TOKEN" | grep -v "ENCRYPTION_KEY" | grep -q .; then
        echo -e "${YELLOW}⚠️  发现可能的敏感信息泄露${NC}"
        ((security_issues++))
    fi

    # 检查权限设置
    if grep -q "permissions:" .github/workflows/*.yml; then
        echo -e "${GREEN}✅ GitHub Actions 权限已正确配置${NC}"
    else
        echo -e "${YELLOW}⚠️  建议在工作流中明确设置权限${NC}"
    fi

    if [[ $security_issues -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  发现 $security_issues 个安全问题${NC}"
    else
        echo -e "${GREEN}✅ 安全配置良好${NC}"
    fi
}

# 主函数
main() {
    echo "🏥 Custom Rustdesk 项目健康检查"
    echo "=================================="

    local total_checks=7
    local passed_checks=0

    # 执行各项检查
    if check_file_permissions; then ((passed_checks++)); fi
    if check_dependencies; then ((passed_checks++)); fi
    if check_environment; then ((passed_checks++)); fi
    if check_gitignore; then ((passed_checks++)); fi
    if check_workflow_syntax; then ((passed_checks++)); fi
    if check_script_syntax; then ((passed_checks++)); fi
    check_security  # 这个检查不影响通过率

    echo ""
    echo "📊 检查结果: $passed_checks/$total_checks 通过"

    if [[ $passed_checks -eq $total_checks ]]; then
        echo -e "${GREEN}🎉 项目健康状态良好！${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠️  项目存在一些问题需要修复${NC}"
        exit 1
    fi
}

# 执行主函数
main "$@"
