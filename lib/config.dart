// Dados do projeto Supabase "agenda-manicure".
// A anon key é pública por natureza: a segurança vem das regras RLS das tabelas.
// NUNCA coloque aqui a chave service_role / secret.
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://ujraozarzrzmkmzzkpnd.supabase.co',
);
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqcmFvemFyenJ6bWttenprcG5kIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI3NzQwNzUsImV4cCI6MjEwODM1MDA3NX0.xoW81EBTs_o3dUQYEjPZu4Xwx2mEyI0rtEWVJrIRRoM',
);
