<script setup lang="ts">
import { ref } from 'vue'
import { supabase } from '../lib/supabase'

const email = ref('')
const password = ref('')
const confirmPassword = ref('')
const isSignUp = ref(false)
const loading = ref(false)
const message = ref('')
const error = ref('')

function switchMode(nextIsSignUp: boolean) {
  isSignUp.value = nextIsSignUp
  error.value = ''
  message.value = ''
  password.value = ''
  confirmPassword.value = ''
}

async function submit() {
  if (!supabase) return
  if (!email.value.trim() || password.value.length < 6) {
    error.value = 'Enter an email and a password with at least 6 characters.'
    return
  }
  if (isSignUp.value && password.value !== confirmPassword.value) {
    error.value = 'Passwords do not match.'
    return
  }

  loading.value = true
  error.value = ''
  message.value = ''

  const credentials = {
    email: email.value.trim(),
    password: password.value,
  }

  const result = isSignUp.value
    ? await supabase.auth.signUp({
        ...credentials,
        options: {
          emailRedirectTo: window.location.origin,
        },
      })
    : await supabase.auth.signInWithPassword(credentials)

  loading.value = false

  if (result.error) {
    error.value = result.error.message
    return
  }

  if (isSignUp.value && !result.data.session) {
    message.value = 'Account created. Check your email to confirm your sign up.'
  }
}

async function resetPassword() {
  if (!supabase) return
  if (!email.value.trim()) {
    error.value = 'Enter your email first.'
    return
  }

  loading.value = true
  error.value = ''
  message.value = ''
  const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.value.trim(), {
    redirectTo: window.location.origin,
  })
  loading.value = false

  if (resetError) {
    error.value = resetError.message
    return
  }

  message.value = 'Password reset link sent to your email.'
}
</script>

<template>
  <main class="auth-page">
    <section class="auth-shell">
      <div class="brand-panel">
        <p class="eyebrow">Sari-Sari Store</p>
        <h1>Store Management</h1>
        <p class="sub">Inventory, sales, reports, and settings for your own account.</p>
        <div class="mini-stats">
          <span>Private Data</span>
          <span>Live Reports</span>
          <span>Secure Access</span>
        </div>
      </div>

      <div class="auth-panel">
        <div class="panel-top">
          <div>
            <p class="eyebrow">Account</p>
            <h2>{{ isSignUp ? 'Create account' : 'Welcome back' }}</h2>
          </div>
          <div class="mode-tabs" aria-label="Authentication mode">
            <button :class="{ active: !isSignUp }" @click="switchMode(false)">Sign In</button>
            <button :class="{ active: isSignUp }" @click="switchMode(true)">Sign Up</button>
          </div>
        </div>

        <div class="field">
          <label>Email</label>
          <input v-model="email" type="email" autocomplete="email" placeholder="you@example.com" />
        </div>

        <div class="field">
          <label>Password</label>
          <input
            v-model="password"
            type="password"
            :autocomplete="isSignUp ? 'new-password' : 'current-password'"
            placeholder="At least 6 characters"
            @keyup.enter="submit"
          />
        </div>

        <div v-if="isSignUp" class="field">
          <label>Confirm Password</label>
          <input
            v-model="confirmPassword"
            type="password"
            autocomplete="new-password"
            placeholder="Repeat password"
            @keyup.enter="submit"
          />
        </div>

        <p v-if="error" class="error">{{ error }}</p>
        <p v-if="message" class="message">{{ message }}</p>

        <button class="primary-btn" :disabled="loading" @click="submit">
          {{ loading ? 'Please wait...' : isSignUp ? 'Create Account' : 'Sign In' }}
        </button>

        <button v-if="!isSignUp" class="link-btn" :disabled="loading" @click="resetPassword">
          Forgot password?
        </button>
      </div>
    </section>
  </main>
</template>

<style scoped>
.auth-page {
  min-height: 100vh;
  display: grid;
  place-items: center;
  padding: 24px;
  background:
    linear-gradient(90deg, rgba(2, 6, 23, 0.82), rgba(15, 23, 42, 0.68)),
    url('/img.jpg');
  background-size: cover;
  background-position: center;
}

.auth-shell {
  width: min(920px, 100%);
  display: grid;
  grid-template-columns: minmax(0, 1fr) 420px;
  gap: 16px;
  align-items: stretch;
}

.brand-panel,
.auth-panel {
  background: rgba(15, 23, 42, 0.92);
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 16px;
  padding: 24px;
  box-shadow: 0 24px 70px rgba(0,0,0,0.45);
}

.brand-panel {
  min-height: 430px;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  background:
    linear-gradient(180deg, rgba(15, 23, 42, 0.38), rgba(15, 23, 42, 0.94)),
    url('/img.jpg');
  background-size: cover;
  background-position: center;
}

.eyebrow {
  margin: 0 0 8px;
  color: #6ee7b7;
  font-size: 12px;
  font-weight: 800;
  text-transform: uppercase;
}

h1 {
  margin: 0;
  font-size: 36px;
}

h2 {
  margin: 0;
  font-size: 24px;
}

.sub {
  margin: 8px 0 20px;
  color: #94a3b8;
  font-size: 14px;
  line-height: 1.5;
}

.mini-stats {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.mini-stats span {
  padding: 6px 10px;
  border-radius: 999px;
  border: 1px solid rgba(34,197,94,0.28);
  background: rgba(34,197,94,0.14);
  color: #6ee7b7;
  font-size: 12px;
  font-weight: 700;
}

.panel-top {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 14px;
  margin-bottom: 20px;
}

.mode-tabs {
  display: grid;
  grid-template-columns: 1fr 1fr;
  padding: 3px;
  border-radius: 10px;
  background: rgba(255,255,255,0.06);
  border: 1px solid rgba(255,255,255,0.1);
}

.mode-tabs button {
  width: auto;
  margin: 0;
  padding: 7px 10px;
  border-radius: 8px;
  background: transparent;
  color: #94a3b8;
  font-size: 12px;
}

.mode-tabs button.active {
  background: rgba(34,197,94,0.18);
  color: #6ee7b7;
}

.field {
  margin-bottom: 14px;
}

label {
  display: block;
  margin-bottom: 6px;
  color: #d1d5db;
  font-size: 13px;
  font-weight: 700;
}

input {
  width: 100%;
  padding: 11px 12px;
  border-radius: 10px;
  border: 1px solid rgba(255,255,255,0.1);
  background: #111827;
  color: white;
  outline: none;
  font-size: 14px;
}

input:focus {
  border-color: #22c55e;
}

.primary-btn,
.link-btn {
  width: 100%;
  margin-top: 10px;
  padding: 11px;
  border: none;
  border-radius: 10px;
  background: linear-gradient(135deg, #059669, #34d399);
  color: white;
  font-size: 14px;
  font-weight: 800;
  cursor: pointer;
}

button:disabled {
  cursor: wait;
  opacity: 0.7;
}

.link-btn {
  background: transparent;
  color: #6ee7b7;
}

.error,
.message {
  margin: 8px 0 0;
  padding: 10px 12px;
  border-radius: 10px;
  font-size: 13px;
}

.error {
  color: #fca5a5;
  background: rgba(239,68,68,0.15);
}

.message {
  color: #6ee7b7;
  background: rgba(34,197,94,0.14);
}

@media (max-width: 760px) {
  .auth-page {
    padding: 16px;
  }

  .auth-shell {
    grid-template-columns: 1fr;
  }

  .brand-panel {
    min-height: 220px;
  }

  h1 {
    font-size: 30px;
  }

  .panel-top {
    flex-direction: column;
  }

  .mode-tabs {
    width: 100%;
  }
}
</style>
