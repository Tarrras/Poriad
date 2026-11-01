// Підтвердження видалення акаунта без Deno: node supabase/functions/delete-account/reauth.test.mjs
import assert from "node:assert/strict";
import { freshLogin, needsReauth } from "./reauth.ts";

assert.equal(needsReauth(["email"]), true);
assert.equal(needsReauth(["google", "email"]), true);
assert.equal(needsReauth([]), true, "unknown providers: ask");
assert.equal(needsReauth(["google"]), false);
assert.equal(needsReauth(["apple"]), false);

// Справжній вигляд access-токена Supabase: base64url без вирівнювання, кирилиця в метаданих.
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const jwt = (claims) => `${b64({ alg: "HS256", typ: "JWT" })}.${b64({ sub: "u", user_metadata: { display_name: "Олена" }, ...claims })}.sig`;
const now = 1_762_000_000;

assert.equal(freshLogin(jwt({ amr: [{ method: "otp", timestamp: now - 60 }] }), now), true, "code from mail a minute ago");
assert.equal(freshLogin(jwt({ amr: [{ method: "otp", timestamp: now - 600 }] }), now), true, "exactly ten minutes");
assert.equal(freshLogin(jwt({ amr: [{ method: "otp", timestamp: now - 601 }] }), now), false, "older than ten minutes");
assert.equal(freshLogin(jwt({ amr: [{ method: "password", timestamp: now - 86_400 }, { method: "oauth", timestamp: now - 5 }] }), now), true,
  "any method of the session counts");
assert.equal(freshLogin(jwt({ amr: [{ method: "otp", timestamp: String(now) }] }), now), false, "timestamp must be a number");
assert.equal(freshLogin(jwt({}), now), false, "no amr");
assert.equal(freshLogin(jwt({ amr: "otp" }), now), false);
assert.equal(freshLogin("not-a-jwt", now), false);
assert.equal(freshLogin("a.!!!.c", now), false);

console.log("reauth: ok");
