# Deployment

This is a Vue 3 + Vite frontend with Supabase Auth and database storage. It can be hosted publicly on Vercel, Netlify, GitHub Pages, or any static host that serves the `dist` folder.

## 1. Create Supabase

1. Go to https://supabase.com and create a free project.
2. Open the project dashboard.
3. Go to SQL Editor.
4. Paste and run the SQL from `supabase/schema.sql`.
5. Go to Project Settings > API.
6. Copy:
   - Project URL
   - anon/public key

The SQL creates private tables for `products`, `sales`, and `store_settings`. Row Level Security is enabled so signed-in users can only read and write rows that belong to their own Supabase user ID.

## 2. Add Local Env Vars

Create a `.env` file in the project root:

```sh
VITE_SUPABASE_URL=https://your-project-ref.supabase.co
VITE_SUPABASE_ANON_KEY=your-supabase-anon-key
```

Use `.env.example` as the template.

## 3. Configure Supabase Auth

In Supabase:

1. Go to Authentication > Providers.
2. Enable Email.
3. For easiest testing, turn off email confirmations. For production, keep confirmations on.
4. Go to Authentication > URL Configuration.
5. Add your final site URL after deployment.

## Recommended: Vercel or Netlify

1. Push this project to a GitHub repository.
2. Import the repository in Vercel or Netlify.
3. Use these build settings if the platform does not auto-detect them:
   - Build command: `npm run build`
   - Output/publish directory: `dist`
   - Install command: `npm install`
4. Add these environment variables in the hosting dashboard:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
5. Deploy the production branch.

## Local Production Check

```sh
npm install
npm run build
npm run preview
```

## Important Data Note

Products, sales, and store settings are now saved to Supabase per signed-in user. Each row includes a `user_id`, and Supabase Row Level Security prevents users from accessing other users' records.
