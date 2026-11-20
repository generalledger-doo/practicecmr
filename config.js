// Practice Desk CRM – connection settings.
//
// Leave both values empty to keep records in this browser only.
// Fill them in to use the shared online database (Supabase). Both are found in the
// Supabase dashboard under Project Settings -> API (or "Connect"):
//   supabaseUrl      the Project URL, e.g. https://abcdefghijkl.supabase.co
//   supabaseAnonKey  the "anon" / "publishable" key (NOT the service_role / secret key)
//
// The anon key is meant to be public: row-level security in supabase/schema.sql
// decides who can see anything. Never put the service_role key here.
window.PRACTICE_DESK_CONFIG = {
  supabaseUrl: "",
  supabaseAnonKey: ""
};
