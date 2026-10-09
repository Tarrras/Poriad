import {useState} from 'react';
import {continueRender, delayRender, staticFile} from 'remotion';

// Шрифти ті самі, що на сайті й у застосунку; Inter розбитий на кирилицю й латиницю, як на сайті
const CYR = 'U+0301,U+0400-045F,U+0490-0491,U+04B0-04B1,U+2116';
const LAT = 'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD';
const FONTS: [string, string, string, string?, string?][] = [
  ['Inter', 'inter-cyrillic-400-normal.woff2', '400', CYR],
  ['Inter', 'inter-cyrillic-600-normal.woff2', '600', CYR],
  ['Inter', 'inter-latin-400-normal.woff2', '400', LAT],
  ['Inter', 'inter-latin-600-normal.woff2', '600', LAT],
  ['Unbounded', 'unbounded-cyrillic.woff2', '200 900', CYR],
  ['Unbounded', 'unbounded-latin.woff2', '200 900', LAT],
];
export const useFonts = () => {
  const [handle] = useState(() => {
    const h = delayRender('fonts');
    Promise.all(FONTS.map(([family, file, weight, unicodeRange, style]) =>
      new FontFace(family, `url(${staticFile('fonts/' + file)})`, {weight, ...(unicodeRange && {unicodeRange}), ...(style && {style})}).load()
        .then((f) => document.fonts.add(f)),
    )).then(() => continueRender(h));
    return h;
  });
  return handle;
};
