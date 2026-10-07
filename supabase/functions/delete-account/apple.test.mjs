// Відкликання токенів Apple без Deno: node supabase/functions/delete-account/apple.test.mjs
import assert from "node:assert/strict";
import { clientSecret, revokeApple } from "./apple.ts";

const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey)).toString("base64");
// Як у секреті: PEM з буквальними `\n`.
const key = `-----BEGIN PRIVATE KEY-----\\n${pkcs8.match(/.{1,64}/g).join("\\n")}\\n-----END PRIVATE KEY-----`;
const config = { teamId: "TEAM123456", clientId: "app.poriad.ios", keyId: "KEY1234567", key };

// client_secret: заголовок і claims, яких чекає Apple, і справжній підпис ES256.
const jwt = await clientSecret(config, 1_700_000_000_000);
const [h, p, s] = jwt.split(".");
const decode = (part) => JSON.parse(Buffer.from(part, "base64url").toString());
assert.deepEqual(decode(h), { alg: "ES256", kid: "KEY1234567" });
assert.deepEqual(decode(p), { iss: "TEAM123456", iat: 1_700_000_000, exp: 1_700_000_300, aud: "https://appleid.apple.com", sub: "app.poriad.ios" });
assert.ok(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, Buffer.from(s, "base64url"), new TextEncoder().encode(`${h}.${p}`)));

// Код міняється на refresh token, і відкликається саме він.
const calls = [];
const apple = (tokenStatus, tokenBody) => async (url, init) => {
  const form = Object.fromEntries(new URLSearchParams(init.body));
  calls.push({ url, form });
  if (url.endsWith("/auth/token")) return new Response(JSON.stringify(tokenBody), { status: tokenStatus });
  return new Response("", { status: 200 });
};
await revokeApple("code-1", config, apple(200, { refresh_token: "rt-1", access_token: "at-1" }));
assert.equal(calls.length, 2);
assert.equal(calls[0].url, "https://appleid.apple.com/auth/token");
assert.equal(calls[0].form.grant_type, "authorization_code");
assert.equal(calls[0].form.code, "code-1");
assert.equal(calls[0].form.client_id, "app.poriad.ios");
assert.equal(calls[1].url, "https://appleid.apple.com/auth/revoke");
assert.deepEqual([calls[1].form.token, calls[1].form.token_type_hint], ["rt-1", "refresh_token"]);

// Прострочений код — помилка з причиною, і до revoke справа не доходить.
calls.length = 0;
await assert.rejects(revokeApple("old", config, apple(400, { error: "invalid_grant" })), /apple token 400 invalid_grant/);
assert.equal(calls.length, 1);

console.log("apple revoke: ok");
