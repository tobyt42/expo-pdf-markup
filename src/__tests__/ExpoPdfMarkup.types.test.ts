import type { ExpoPdfMarkupViewProps } from '../ExpoPdfMarkup.types';

/**
 * Type-level tests — these validate at compile time. If the file compiles, the tests pass.
 */

function accept(_props: ExpoPdfMarkupViewProps) {
  // no-op, used only for type checking
}

it('compiles with valid and invalid prop combinations', () => {
  // source is required
  // @ts-expect-error: source is missing
  accept({});

  // Valid minimal props
  accept({ source: 'test.pdf' });

  // Valid full props with callbacks
  accept({
    source: 'test.pdf',
    page: 1,
    onPageChanged: (_e) => {},
    onLoadComplete: (_e) => {},
    onError: (_e) => {},
    style: { flex: 1 },
  });

  expect(true).toBe(true);
});

it('passes text input request context to onTextInputRequested', () => {
  accept({
    source: 'test.pdf',
    onTextInputRequested: async (request) => {
      if (request.mode === 'edit') {
        return request.currentText ?? null;
      }

      return String(request.page);
    },
  });

  expect(true).toBe(true);
});
