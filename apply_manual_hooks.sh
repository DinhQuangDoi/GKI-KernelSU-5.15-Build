#!/bin/bash
# ================================================================
# apply_manual_hooks.sh
# Apply ReSukiSU manual hooks to kernel source for KernelSU integration
#
# Usage: Run from kernel source root (common/)
#   bash /path/to/apply_manual_hooks.sh
# ================================================================
set -euo pipefail

PATCHED=0
SKIPPED=0
FAILED=0

already_patched() {
	grep -q "ksu_handle_" "$1" 2>/dev/null
}

# ================================================================
# 1. fs/stat.c - stat hooks
# ================================================================
file="fs/stat.c"
if [ ! -f "$file" ]; then
	echo "Skip (not found): $file"; ((SKIPPED++)) || true
elif already_patched "$file"; then
	echo "Skip (already patched): $file"; ((SKIPPED++)) || true
else
	echo "Patching: $file"

	# Add extern declarations after newlstat function (before #if !defined guard)
	perl -i -0777 -pe '
		# Find the end of newlstat and insert extern declarations before the #if guard
		s{
			(return\s+cp_new_stat\(\&stat,\s*statbuf\);\s*\n\s*\})
			(\s*\n\s*\#if\s+\!defined\(__ARCH_WANT_STAT64\))
		}{
			$1 . "\n" .
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"__attribute__((hot))\n" .
			"extern int ksu_handle_stat(int *dfd, const char __user **filename_user,\n" .
			"\t\t\t\tint *flags);\n" .
			"extern void ksu_handle_newfstat_ret(unsigned int *fd,\n" .
			"\t\t\t\tstruct stat __user **statbuf_ptr);\n" .
			"#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)\n" .
			"extern void ksu_handle_fstat64_ret(unsigned long *fd,\n" .
			"\t\t\t\tstruct stat64 __user **statbuf_ptr);\n" .
			"#endif\n" .
			"#endif\n\n" .
			$2
		}xe
	' "$file"

	# Add ksu_handle_stat call in newfstatat after local vars
	perl -i -0777 -pe '
		s{
			(SYSCALL_DEFINE4\(newfstatat,\s*int,\s*dfd,\s*const\s+char\s+__user\s*\*,\s*filename,\s*struct\s+stat\s+__user\s*\*,\s*statbuf,\s*int,\s*flag\)\s*\n\s*\{\s*\n\s*struct\s+kstat\s+stat;\s*\n\s*int\s+error;)
		}{
			$1 . "\n" .
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tksu_handle_stat(&dfd, &filename, &flag);\n" .
			"#endif"
		}xe
	' "$file"

	# Add ksu_handle_stat call in fstatat64 after local vars
	perl -i -0777 -pe '
		s{
			(SYSCALL_DEFINE4\(fstatat64,\s*int,\s*dfd,\s*const\s+char\s+__user\s*\*,\s*filename,\s*struct\s+stat64\s+__user\s*\*,\s*statbuf,\s*int,\s*flag\)\s*\n\s*\{\s*\n\s*struct\s+kstat\s+stat;\s*\n\s*int\s+error;)
		}{
			$1 . "\n" .
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tksu_handle_stat(&dfd, &filename, &flag);\n" .
			"#endif"
		}xe
	' "$file"

	# Add ksu_handle_newfstat_ret before return in newfstat
	perl -i -0777 -pe '
		s{
			(if\s*\(!error\)\s*\n\s+error\s*=\s*cp_new_stat\(\&stat,\s*statbuf\);\s*\n)
			(\s+return\s+error;)
		}{
			$1 . "\t" . '#ifdef CONFIG_KSU_MANUAL_HOOK' . "\n" .
			"\tksu_handle_newfstat_ret(&fd, &statbuf);\n" .
			"\t" . '#endif' . "\n" .
			$2
		}xe
	' "$file"

	# Add ksu_handle_fstat64_ret before return in fstat64
	perl -i -0777 -pe '
		s{
			(if\s*\(!error\)\s*\n\s+error\s*=\s*cp_new_stat64\(\&stat,\s*statbuf\);\s*\n)
			(\s+return\s+error;)
		}{
			$1 . "\t" . '#ifdef CONFIG_KSU_MANUAL_HOOK' . "\n" .
			"\tksu_handle_fstat64_ret(&fd, &statbuf);\n" .
			"\t" . '#endif' . "\n" .
			$2
		}xe
	' "$file"

	if already_patched "$file"; then
		echo "Patched: $file"; ((PATCHED++)) || true
	else
		echo "::error::Patch failed: $file"; ((FAILED++)) || true
	fi
fi

# ================================================================
# 2. fs/exec.c - execve hooks (3.14+ style: ksu_handle_execveat)
# ================================================================
file="fs/exec.c"
if [ ! -f "$file" ]; then
	echo "Skip (not found): $file"; ((SKIPPED++)) || true
elif already_patched "$file"; then
	echo "Skip (already patched): $file"; ((SKIPPED++)) || true
else
	echo "Patching: $file"

	# Add extern declaration before do_execve and hook call inside do_execve
	perl -i -0777 -pe '
		# Insert extern declaration before do_execve
		s{
			(int\s+do_execve\s*\(\s*struct\s+filename\s*\*\s*filename,)
		}{
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"__attribute__((hot))\n" .
			"extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n" .
			"\t\t\t\tvoid *argv, void *envp, int *flags);\n" .
			"#endif\n\n" .
			$1
		}xe
	' "$file"

	# Add ksu_handle_execveat call in do_execve after local var setup
	perl -i -0777 -pe '
		s{
			(int\s+do_execve\s*\(\s*struct\s+filename\s*\*\s*filename,\s*)
			(.*?)
			(\s*struct\s+user_arg_ptr\s+envp\s*=\s*\{\s*\.ptr\.native\s*=\s*__envp\s*\}\s*;)
		}{
			my $decl = $1;
			my $mid = $2;
			my $envp_line = $3;
			$decl . $mid . $envp_line . "\n" .
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\n" .
			"#endif"
		}xse
	' "$file"

	# Add ksu_handle_execveat in compat_do_execve after local var setup
	perl -i -0777 -pe '
		s{
			(static\s+int\s+compat_do_execve\s*\(\s*struct\s+filename\s*\*\s*filename,)
			(.*?)
			(\.ptr\.compat\s*=\s*__envp\s*\}\s*;)
		}{
			my $decl = $1;
			my $mid = $2;
			my $envp_end = $3;
			$decl . $mid . $envp_end . "\n" .
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\n" .
			"#endif"
		}xse
	' "$file"

	if already_patched "$file"; then
		echo "Patched: $file"; ((PATCHED++)) || true
	else
		echo "::error::Patch failed: $file"; ((FAILED++)) || true
	fi
fi

# ================================================================
# 3. fs/open.c - faccessat hook (4.19+ style)
# ================================================================
file="fs/open.c"
if [ ! -f "$file" ]; then
	echo "Skip (not found): $file"; ((SKIPPED++)) || true
elif already_patched "$file"; then
	echo "Skip (already patched): $file"; ((SKIPPED++)) || true
else
	echo "Patching: $file"

	# Add extern declaration before SYSCALL_DEFINE3(faccessat, ...)
	perl -i -0777 -pe '
		s{
			(SYSCALL_DEFINE3\(faccessat,\s*int,\s*dfd,\s*const\s+char\s+__user\s*\*,\s*filename,\s*int,\s*mode\))
		}{
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"__attribute__((hot))\n" .
			"extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n" .
			"\t\t\t\tint *mode, int *flags);\n" .
			"#endif\n\n" .
			$1
		}xe
	' "$file"

	# Add ksu_handle_faccessat call at beginning of faccessat function body
	perl -i -0777 -pe '
		s{
			(SYSCALL_DEFINE3\(faccessat,\s*int,\s*dfd,\s*const\s+char\s+__user\s*\*,\s*filename,\s*int,\s*mode\)\s*\n\s*\{\s*\n)
			(\s*return\s+do_faccessat\(dfd,\s*filename,\s*mode\);)
		}{
			$1 .
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n" .
			"#endif\n" .
			$2
		}xe
	' "$file"

	if already_patched "$file"; then
		echo "Patched: $file"; ((PATCHED++)) || true
	else
		echo "::error::Patch failed: $file"; ((FAILED++)) || true
	fi
fi

# ================================================================
# 4. kernel/reboot.c - sys_reboot hook (3.11+ style)
# ================================================================
file="kernel/reboot.c"
if [ ! -f "$file" ]; then
	echo "Skip (not found): $file"; ((SKIPPED++)) || true
elif already_patched "$file"; then
	echo "Skip (already patched): $file"; ((SKIPPED++)) || true
else
	echo "Patching: $file"

	# Add extern declaration before SYSCALL_DEFINE4(reboot, ...)
	perl -i -0777 -pe '
		s{
			(SYSCALL_DEFINE4\(reboot,\s*int,\s*magic1,\s*int,\s*magic2,\s*unsigned\s+int,\s*cmd,)
		}{
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"extern int ksu_handle_sys_reboot(int magic1, int magic2,\n" .
			"\t\t\t\tunsigned int cmd, void __user **arg);\n" .
			"#endif\n\n" .
			$1
		}xe
	' "$file"

	# Add ksu_handle_sys_reboot call after local vars in reboot syscall
	perl -i -0777 -pe '
		s{
			(SYSCALL_DEFINE4\(reboot,\s*int,\s*magic1,\s*int,\s*magic2,\s*unsigned\s+int,\s*cmd,\s*void\s+__user\s*\*,\s*arg\)\s*\n\s*\{\s*\n)
			(.*?)
			(int\s+ret\s*=\s*0;)
		}{
			my $sig = $1;
			my $mid = $2;
			my $ret = $3;
			$sig . $mid . $ret . "\n" .
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n" .
			"#endif"
		}xse
	' "$file"

	if already_patched "$file"; then
		echo "Patched: $file"; ((PATCHED++)) || true
	else
		echo "::error::Patch failed: $file"; ((FAILED++)) || true
	fi
fi

# ================================================================
# 5. drivers/input/input.c - input hook
# ================================================================
file="drivers/input/input.c"
if [ ! -f "$file" ]; then
	echo "Skip (not found): $file"; ((SKIPPED++)) || true
elif grep -q "ksu_input_hook" "$file" 2>/dev/null; then
	echo "Skip (already patched): $file"; ((SKIPPED++)) || true
else
	echo "Patching: $file"

	# Add extern declarations and hook call in input_event
	perl -i -0777 -pe '
		s{
			(void\s+input_event\s*\(\s*struct\s+input_dev\s*\*\s*dev,)
		}{
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"extern bool ksu_input_hook __read_mostly;\n" .
			"extern __attribute__((cold)) int ksu_handle_input_handle_event(\n" .
			"\t\t\tunsigned int *type, unsigned int *code, int *value);\n" .
			"#endif\n\n" .
			$1
		}xe
	' "$file"

	# Add ksu_input_hook check inside input_event
	perl -i -0777 -pe '
		s{
			(void\s+input_event\s*\(\s*struct\s+input_dev\s*\*\s*dev,)
			(.*?)
			(unsigned\s+long\s+flags;)
		}{
			my $sig = $1;
			my $mid = $2;
			my $flags = $3;
			$sig . $mid . $flags . "\n\n" .
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tif (unlikely(ksu_input_hook))\n" .
			"\t\tksu_handle_input_handle_event(&type, &code, &value);\n" .
			"#endif"
		}xse
	' "$file"

	if grep -q "ksu_input_hook" "$file" 2>/dev/null; then
		echo "Patched: $file"; ((PATCHED++)) || true
	else
		echo "::error::Patch failed: $file"; ((FAILED++)) || true
	fi
fi

# ================================================================
# 6. kernel/sys.c - setuid hook (4.17+ style: __sys_setresuid)
# ================================================================
file="kernel/sys.c"
if [ ! -f "$file" ]; then
	echo "Skip (not found): $file"; ((SKIPPED++)) || true
elif already_patched "$file"; then
	echo "Skip (already patched): $file"; ((SKIPPED++)) || true
else
	echo "Patching: $file"

	# Add extern declaration before __sys_setresuid
	perl -i -0777 -pe '
		s{
			(long\s+__sys_setresuid\s*\(\s*uid_t\s+ruid,\s*uid_t\s+euid,\s*uid_t\s+suid\))
		}{
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"extern int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid);\n" .
			"#endif\n\n" .
			$1
		}xe
	' "$file"

	# Add ksu_handle_setresuid call in __sys_setresuid after declarations
	perl -i -0777 -pe '
		s{
			(long\s+__sys_setresuid\s*\(\s*uid_t\s+ruid,\s*uid_t\s+euid,\s*uid_t\s+suid\)\s*\n\s*\{\s*\n)
			(.*?)
			(kruid\s*=\s*make_kuid\(ns,\s*ruid\);)
		}{
			my $sig = $1;
			my $mid = $2;
			my $mk = $3;
			$sig . $mid .
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\t(void)ksu_handle_setresuid(ruid, euid, suid);\n" .
			"#endif\n\n" .
			"\t" . $mk
		}xse
	' "$file"

	if already_patched "$file"; then
		echo "Patched: $file"; ((PATCHED++)) || true
	else
		echo "::error::Patch failed: $file"; ((FAILED++)) || true
	fi
fi

# ================================================================
# 7. fs/read_write.c - sys_read hook (4.19+ style)
# ================================================================
file="fs/read_write.c"
if [ ! -f "$file" ]; then
	echo "Skip (not found): $file"; ((SKIPPED++)) || true
elif already_patched "$file"; then
	echo "Skip (already patched): $file"; ((SKIPPED++)) || true
else
	echo "Patching: $file"

	# Add extern declarations before SYSCALL_DEFINE3(read, ...)
	perl -i -0777 -pe '
		s{
			(SYSCALL_DEFINE3\(read,\s*unsigned\s+int,\s*fd,\s*char\s+__user\s*\*,\s*buf,\s*size_t,\s*count\))
		}{
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"extern bool ksu_init_rc_hook __read_mostly;\n" .
			"extern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\n" .
			"\t\t\t\tchar __user **buf_ptr, size_t *count_ptr);\n" .
			"#endif\n\n" .
			$1
		}xe
	' "$file"

	# Add ksu_init_rc_hook check inside read syscall
	perl -i -0777 -pe '
		s{
			(SYSCALL_DEFINE3\(read,\s*unsigned\s+int,\s*fd,\s*char\s+__user\s*\*,\s*buf,\s*size_t,\s*count\)\s*\n\s*\{\s*\n)
			(return\s+ksys_read\(fd,\s*buf,\s*count\);)
		}{
			$1 .
			"#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tif (unlikely(ksu_init_rc_hook))\n" .
			"\t\tksu_handle_sys_read(fd, &buf, &count);\n" .
			"#endif\n" .
			"\t" . $2
		}xe
	' "$file"

	if already_patched "$file"; then
		echo "Patched: $file"; ((PATCHED++)) || true
	else
		echo "::error::Patch failed: $file"; ((FAILED++)) || true
	fi
fi

# ================================================================
# Summary
# ================================================================
echo ""
echo "=== Manual hooks patch complete: ${PATCHED} patched, ${SKIPPED} skipped, ${FAILED} failed ==="

if [ "$FAILED" -gt 0 ]; then
	exit 1
fi
