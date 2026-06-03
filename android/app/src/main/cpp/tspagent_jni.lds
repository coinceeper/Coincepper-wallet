/* فقط JNI_OnLoad به‌صورت global export؛ بقیه در نماد local می‌مانند. */
{
  global: JNI_OnLoad;
  local: *;
};
