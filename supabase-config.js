// Paste your Supabase values (Project Settings > API). Use the publishable (anon) key ONLY.
const SUPABASE_URL = "https://noawzclgoxprsntgjlew.supabase.co";
const SUPABASE_KEY = "sb_publishable_gjzgcqA3oQcCiIgsCxgBXQ_HRFQc4mn";
const sb = (SUPABASE_URL.startsWith("http") && window.supabase)
  ? window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY) : null;
