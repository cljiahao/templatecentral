// Comment markers inside literals are not comments.
export const url = 'https://example.com/a//b';
export const block = "/* not a comment */";
export const tpl = `// nope ${url} /* nope */`;
export const re = /\/\/ not [(]a comment[)]/;
export const slashes = /[/]{2}/;
export const aside = "// (aside) trailing";
