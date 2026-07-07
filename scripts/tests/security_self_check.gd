# security_self_check.gd
# Quick assert-based checks for the security fixes.
# Run it as a scene root or via: godot --script res://scripts/tests/security_self_check.gd
extends Node


func _ready() -> void:
	_test_path_validation()
	_test_formula_sanitization()
	_test_hmac_key()
	_test_tres_validation()
	print("=== security_self_check: ALL PASSED ===")


func _test_path_validation() -> void:
	# ../ must be rejected outright
	assert(not SaveManager._validate_path("../etc/passwd"), "should reject ../")
	assert(not SaveManager._validate_path("user://saves/../slot_0.json"), "should reject embedded ../")
	# absolute paths are not allowed
	assert(not SaveManager._validate_path("/etc/passwd"), "should reject absolute path")
	# a normal user:// path is fine
	assert(SaveManager._validate_path("user://saves/slot_0.json"), "should accept normal path")
	print("  [OK] path validation rejects traversal")


func _test_formula_sanitization() -> void:
	# exec( is a hard reject — keyword + paren
	assert(VerificationPipeline._sanitize_formula("exec(bad)") == "", "should reject exec(")
	# );  contains paren and semicolon — both outside allowed set
	assert(VerificationPipeline._sanitize_formula("foo);") == "", "should reject );")
	# full SMT2 snippet should be stripped
	assert(VerificationPipeline._sanitize_formula("(assert (= x 1))") == "", "should reject parens")
	# plain math expression is fine
	var ok := VerificationPipeline._sanitize_formula("a + b = c")
	assert(ok == "a + b = c", "should accept basic math")
	print("  [OK] formula sanitization rejects injection")


func _test_hmac_key() -> void:
	var key := SaveManager._derive_hmac_key()
	# SHA256 digest is always 32 bytes
	assert(key.size() == 32, "HMAC key should be 32 bytes")
	# the key must differ from a salt-only key, proving OS.get_unique_id() is mixed in
	var uid := OS.get_unique_id()
	if not uid.is_empty():
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update("intuita_v1_salt".to_utf8_buffer())
		var salt_only_key := ctx.finish()
		assert(key != salt_only_key, "HMAC key must incorporate OS.get_unique_id()")
	print("  [OK] hmac key uses OS.get_unique_id()")


func _test_tres_validation() -> void:
	# missing file fails closed
	assert(not SaveManager.validate_tres_file("res://nonexistent_file.tres"), "should reject missing file")
	print("  [OK] tres validation fails closed")
