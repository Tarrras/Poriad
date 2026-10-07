import {Composition} from 'remotion';
import {A1, A1_FRAMES} from './A1';
import {Ad15} from './Ad15';
import {P2, P2_FRAMES, P3, P3_FRAMES, P4, P4_FRAMES} from './Product';
import {PROMO_FRAMES, Promo} from './Promo';
import {T1, T1_FRAMES, T2, T2_FRAMES, T3, T3_FRAMES, T5, T5_FRAMES, T7, T7_FRAMES} from './Tiktok';
import {ZOOMER_FRAMES, Zoomer} from './Zoomer';

// 9:16 для Reels і TikTok
export const Root = () => (
  <>
    <Composition id="A1" component={A1} durationInFrames={A1_FRAMES} fps={30} width={1080} height={1920} />
    <Composition id="P2" component={P2} durationInFrames={P2_FRAMES} fps={30} width={1080} height={1920} defaultProps={{music: true}} />
    <Composition id="P3" component={P3} durationInFrames={P3_FRAMES} fps={30} width={1080} height={1920} defaultProps={{music: true}} />
    <Composition id="P4" component={P4} durationInFrames={P4_FRAMES} fps={30} width={1080} height={1920} defaultProps={{music: true}} />
    <Composition id="T1" component={T1} durationInFrames={T1_FRAMES} fps={30} width={1080} height={1920} defaultProps={{music: true}} />
    <Composition id="T2" component={T2} durationInFrames={T2_FRAMES} fps={30} width={1080} height={1920} defaultProps={{music: true}} />
    <Composition id="T3" component={T3} durationInFrames={T3_FRAMES} fps={30} width={1080} height={1920} defaultProps={{music: true}} />
    <Composition id="T5" component={T5} durationInFrames={T5_FRAMES} fps={30} width={1080} height={1920} defaultProps={{music: true}} />
    <Composition id="T7" component={T7} durationInFrames={T7_FRAMES} fps={30} width={1080} height={1920} defaultProps={{music: true}} />
    <Composition id="Ad15" component={Ad15} durationInFrames={450} fps={30} width={1080} height={1920} />
    <Composition id="Promo" component={Promo} durationInFrames={PROMO_FRAMES} fps={30} width={1080} height={1920} />
    <Composition id="Zoomer" component={Zoomer} durationInFrames={ZOOMER_FRAMES} fps={30} width={1080} height={1920} />
  </>
);
