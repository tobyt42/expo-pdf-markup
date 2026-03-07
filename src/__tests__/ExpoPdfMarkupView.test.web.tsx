import React from 'react';

import ExpoPdfMarkupView from '../ExpoPdfMarkupView.web';

describe('ExpoPdfMarkupView (web)', () => {
  it('is a function component', () => {
    expect(typeof ExpoPdfMarkupView).toBe('function');
  });

  it('returns a valid React element', () => {
    const element = <ExpoPdfMarkupView source="test.pdf" />;
    expect(React.isValidElement(element)).toBe(true);
  });

  it('accepts a style prop without error', () => {
    const element = <ExpoPdfMarkupView source="test.pdf" style={{ backgroundColor: 'red' }} />;
    expect(element.props.style).toEqual({ backgroundColor: 'red' });
  });
});
