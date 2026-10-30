import { classifySwipe } from '../../web/bookMode';

// The same release rule as iOS and Android: a quarter of the view's width, or a fling faster
// than 500 pt/s (0.5 px/ms) in the direction of the drag.
describe('classifySwipe', () => {
  const width = 400;

  it('a slow drag turns once it passes a quarter of the width', () => {
    expect(classifySwipe(-99, 0, width, 0)).toBeNull();
    expect(classifySwipe(-100, 0, width, 0)).toBe('next');
    expect(classifySwipe(100, 0, width, 0)).toBe('previous');
  });

  it('a short drag released fast enough turns in its own direction', () => {
    expect(classifySwipe(-30, 0, width, -0.49)).toBeNull();
    expect(classifySwipe(-30, 0, width, -0.6)).toBe('next');
    expect(classifySwipe(30, 0, width, 0.6)).toBe('previous');
  });

  it('a fling back against the drag settles back', () => {
    expect(classifySwipe(-150, 0, width, 2)).toBeNull();
    expect(classifySwipe(150, 0, width, -2)).toBeNull();
  });

  it('a mostly vertical drag never turns', () => {
    expect(classifySwipe(-150, 200, width, -2)).toBeNull();
  });

  it('swipe left means next on any width', () => {
    expect(classifySwipe(-300, 0, 1000, 0)).toBe('next');
    expect(classifySwipe(-200, 0, 1000, 0)).toBeNull();
  });
});
