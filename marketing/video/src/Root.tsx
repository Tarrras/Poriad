import {Composition} from 'remotion';
import {HYBRID_FRAMES, Hybrid} from './Hybrid';
import {MOTION_FRAMES, Motion} from './Motion';
import {P2, P2_FRAMES, P3, P3_FRAMES} from './Product';

// 9:16 для Reels і TikTok
const props = {fps: 30, width: 1080, height: 1920, defaultProps: {music: true}};
export const Root = () => (
  <>
    <Composition id="Hybrid" component={Hybrid} durationInFrames={HYBRID_FRAMES} {...props} />
    <Composition id="Motion" component={Motion} durationInFrames={MOTION_FRAMES} {...props} />
    <Composition id="P2" component={P2} durationInFrames={P2_FRAMES} {...props} />
    <Composition id="P3" component={P3} durationInFrames={P3_FRAMES} {...props} />
  </>
);
