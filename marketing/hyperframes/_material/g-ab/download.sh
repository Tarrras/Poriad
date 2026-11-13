#!/bin/bash
# Завантажує кліпи серії G A/B (Higgsfield, seedance_2_5, 9:16, 480p, 10 с) у цю папку як h1.mp4 … h10.mp4
cd "$(dirname "$0")"
B=https://d8j0ntlcm91z4.cloudfront.net/user_3Lv2APFcnjrmyhbCgod2kpfsXta
curl -fL -o h1.mp4  $B/hf_20261112_223613_48880efd-5cc5-4690-b1fd-50055e694d53.mp4
curl -fL -o h2.mp4  $B/hf_20261112_224251_45a0175f-4895-4f04-80b4-1eced92e2743.mp4
curl -fL -o h3.mp4  $B/hf_20261112_224718_9f12d8fd-8a40-4e70-9ac6-5b9f20a7a512.mp4
curl -fL -o h4.mp4  $B/hf_20261112_225415_59e143c3-00bc-4602-9833-78de98d04664.mp4
curl -fL -o h5.mp4  $B/hf_20261112_230358_f477702e-a0d1-4998-affb-231d8317fb6f.mp4
curl -fL -o h6.mp4  $B/hf_20261112_231410_85e349cd-1d28-4e21-b2b0-449ce7fb0809.mp4
curl -fL -o h7.mp4  $B/hf_20261112_232020_8d372d0b-b92f-435c-b5b5-f41f8cd61b1c.mp4
curl -fL -o h8.mp4  $B/hf_20261112_232533_2daaa6d7-85fa-403b-a9fd-73d1f3a7acbf.mp4
curl -fL -o h9.mp4  $B/hf_20261112_233135_740a9683-6bdd-4739-b4e1-8038f1a3dc54.mp4
curl -fL -o h10.mp4 $B/hf_20261112_233919_03c86627-b611-4ffa-9f11-da75ab0ae390.mp4
ls -la h*.mp4
