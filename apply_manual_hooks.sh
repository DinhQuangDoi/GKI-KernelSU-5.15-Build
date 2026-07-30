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

# Helper: run a perl script from a heredoc
run_perl() {
	local file="$1"
	local label="$2"
	shift 2
	perl -i -0777 -p "$@" "$file"
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

	# Add extern declarations after newlstat
	perl -i -0777 -pe '
		my $pat1 = qr/(return\s+cp_new_stat\(&stat,\s*statbuf\);\s*\n\s*\})/;
		my $pat2 = qr/(\s*\n\s*\#if\s+\!defined\(__ARCH_WANT_STAT64\))/;
		if (/$pat1$pat2/) {
			my $insert = "#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
				"__attribute__((hot))\n" .
				"extern int ksu_handle_stat(int *dfd, const char __user **filename_user,\n" .
				"\t\t\t\tint *flags);\n" .
				"extern void ksu_handle_newfstat_ret(unsigned int *fd,\n" .
				"\t\t\t\tstruct stat __user **statbuf_ptr);\n" .
				"#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)\n" .
				"extern void ksu_handle_fstat64_ret(unsigned long *fd,\n" .
				"\t\t\t\tstruct stat64 __user **statbuf_ptr);\n" .
				"#endif\n" .
				"#endif\n";
			s/$pat1$pat2/$1\n$insert$2/;
		}
	' "$file"

	# Add ksu_handle_stat in newfstatat body
	perl -i -0777 -pe '
		my $pat = qr/(SYSCALL_DEFINE4\(newfstatat,\s*int,\s*dfd,\s*const\s+char\s+__user\s*\*,\s*filename,\s*struct\s+stat\s+__user\s*\*,\s*statbuf,\s*int,\s*flag\)\s*\n\s*\{\s*\n\s*struct\s+kstat\s+stat;\s*\n\s*int\s+error;)/;
		if (/$pat/) {
			my $hook = "\n#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
				"\tksu_handle_stat(&dfd, &filename, &flag);\n" .
				"#endif";
			s/$pat/$1$hook/;
		}
	' "$file"

	# Add ksu_handle_stat in fstatat64 body
	perl -i -0777 -pe '
		my $pat = qr/(SYSCALL_DEFINE4\(fstatat64,\s*int,\s*dfd,\s*const\s+char\s+__user\s*\*,\s*filename,\s*struct\s+stat64\s+__user\s*\*,\s*statbuf,\s*int,\s*flag\)\s*\n\s*\{\s*\n\s*struct\s+kstat\s+stat;\s*\n\s*int\s+error;)/;
		if (/$pat/) {
			my $hook = "\n#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
				"\tksu_handle_stat(&dfd, &filename, &flag);\n" .
				"#endif";
			s/$pat/$1$hook/;
		}
	' "$file"

	# Add ksu_handle_newfstat_ret before return in newfstat only (not newfstatat)
	perl -i -0777 -pe '
		my $pat = qr/(SYSCALL_DEFINE2\(newfstat,\s*unsigned\s+int,\s*fd,.*?if\s*\(!error\)\s*\n\s+error\s*=\s*cp_new_stat\(&stat,\s*statbuf\);\s*\n)(\s+return\s+error;)/s;
		if (/$pat/) {
			my $hook = "#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
				"\tksu_handle_newfstat_ret(&fd, &statbuf);\n" .
				"#endif\n";
			s/$pat/$1\t$hook$2/s;
		}
	' "$file"

	# Add ksu_handle_fstat64_ret before return in fstat64 only (not fstatat64)
	perl -i -0777 -pe '
		my $pat = qr/(SYSCALL_DEFINE2\(fstat64,\s*unsigned\s+long,\s*fd,.*?if\s*\(!error\)\s*\n\s+error\s*=\s*cp_new_stat64\(&stat,\s*statbuf\);\s*\n)(\s+return\s+error;)/s;
		if (/$pat/) {
			my $hook = "#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
				"\tksu_handle_fstat64_ret(&fd, &statbuf);\n" .
				"#endif\n";
			s/$pat/$1\t$hook$2/s;
		}
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

	# Insert extern declaration before do_execve, and hook call inside do_execve + compat_do_execve
	perl -i -0777 -pe '
		# extern before do_execve
		my $decl = "#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"__attribute__((hot))\n" .
			"extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n" .
			"\t\t\t\tvoid *argv, void *envp, int *flags);\n" .
			"#endif\n";
		s/((?:static\s+)?int\s+do_execve\s*\(\s*struct\s+filename\s*\*\s*filename,)/$decl$1/;

		# ksu_handle_execveat in do_execve body
		my $hook_do = "\n#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\n" .
			"#endif";
		my $pat_do = qr/((?:static\s+)?int\s+do_execve\s*\(.*?struct\s+user_arg_ptr\s+envp\s*=\s*\{\s*\.ptr\.native\s*=\s*__envp\s*\}\s*;)/s;
		s/$pat_do/$1$hook_do/s;

		# ksu_handle_execveat in compat_do_execve body
		my $hook_compat = "\n#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\n" .
			"#endif";
		my $pat_compat = qr/((?:static\s+)?int\s+compat_do_execve\s*\(.*?\.ptr\.compat\s*=\s*__envp\s*\}\s*;)/s;
		s/$pat_compat/$1$hook_compat/s;
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

	perl -i -0777 -pe '
		# Add extern and hook call
		my $decl = "#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"__attribute__((hot))\n" .
			"extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n" .
			"\t\t\t\tint *mode, int *flags);\n" .
			"#endif\n";
		my $pat = qr/(SYSCALL_DEFINE3\(faccessat,\s*int,\s*dfd,\s*const\s+char\s+__user\s*\*,\s*filename,\s*int,\s*mode\))/;
		s/$pat/$decl$1/;

		my $hook = "\n#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n" .
			"#endif\n";
		my $pat2 = qr/(SYSCALL_DEFINE3\(faccessat,\s*int,\s*dfd,\s*const\s+char\s+__user\s*\*,\s*filename,\s*int,\s*mode\)\s*\n\s*\{\s*\n)(\s*return\s+do_faccessat\(dfd,\s*filename,\s*mode\);)/;
		s/$pat2/$1$hook$2/;
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

	perl -i -0777 -pe '
		my $decl = "#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"extern int ksu_handle_sys_reboot(int magic1, int magic2,\n" .
			"\t\t\t\tunsigned int cmd, void __user **arg);\n" .
			"#endif\n";
		my $pat = qr/(SYSCALL_DEFINE4\(reboot,\s*int,\s*magic1,\s*int,\s*magic2,\s*unsigned\s+int,\s*cmd,)/;
		s/$pat/$decl$1/;

		my $hook = "\n#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n" .
			"#endif";
		my $pat2 = qr/(SYSCALL_DEFINE4\(reboot,\s*int,\s*magic1,\s*int,\s*magic2,\s*unsigned\s+int,\s*cmd,\s*void\s+__user\s*\*,\s*arg\)\s*\n\s*\{\s*\n.*?int\s+ret\s*=\s*0;)/s;
		s/$pat2/$1$hook/s;
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

	perl -i -0777 -pe '
		my $decl = "#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"extern bool ksu_input_hook __read_mostly;\n" .
			"extern __attribute__((cold)) int ksu_handle_input_handle_event(\n" .
			"\t\t\tunsigned int *type, unsigned int *code, int *value);\n" .
			"#endif\n";
		my $pat = qr/(void\s+input_event\s*\(\s*struct\s+input_dev\s*\*\s*dev,)/;
		s/$pat/$decl$1/;

		my $hook = "\n#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tif (unlikely(ksu_input_hook))\n" .
			"\t\tksu_handle_input_handle_event(&type, &code, &value);\n" .
			"#endif";
		my $pat2 = qr/(void\s+input_event\s*\(.*?unsigned\s+long\s+flags;)/s;
		s/$pat2/$1$hook/s;
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

	perl -i -0777 -pe '
		my $decl = "#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"extern int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid);\n" .
			"#endif\n";
		my $pat = qr/(long\s+__sys_setresuid\s*\(\s*uid_t\s+ruid,\s*uid_t\s+euid,\s*uid_t\s+suid\))/;
		s/$pat/$decl$1/;

		my $hook = "\n#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\t(void)ksu_handle_setresuid(ruid, euid, suid);\n" .
			"#endif\n";
		my $pat2 = qr/(long\s+__sys_setresuid\s*\(.*?\n\s*\{\s*\n)(.*?\n)(\s*kruid\s*=\s*make_kuid\(ns,\s*ruid\);)/s;
		if (/$pat2/) {
			s/$pat2/$1$2$hook\t$3/s;
		}
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

	perl -i -0777 -pe '
		my $decl = "#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"extern bool ksu_init_rc_hook __read_mostly;\n" .
			"extern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\n" .
			"\t\t\t\tchar __user **buf_ptr, size_t *count_ptr);\n" .
			"#endif\n";
		my $pat = qr/(SYSCALL_DEFINE3\(read,\s*unsigned\s+int,\s*fd,\s*char\s+__user\s*\*,\s*buf,\s*size_t,\s*count\))/;
		s/$pat/$decl$1/;

		my $hook = "\n#ifdef CONFIG_KSU_MANUAL_HOOK\n" .
			"\tif (unlikely(ksu_init_rc_hook))\n" .
			"\t\tksu_handle_sys_read(fd, &buf, &count);\n" .
			"#endif\n";
		my $pat2 = qr/(SYSCALL_DEFINE3\(read,\s*unsigned\s+int,\s*fd,\s*char\s+__user\s*\*,\s*buf,\s*size_t,\s*count\)\s*\n\s*\{\s*\n)(return\s+ksys_read\(fd,\s*buf,\s*count\);)/;
		s/$pat2/$1$hook\t$2/;
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
