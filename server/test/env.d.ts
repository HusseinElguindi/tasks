// The two Vite features the fixture test uses, without depending on vite/client.
declare module "*?raw" {
  const text: string;
  export default text;
}
interface ImportMeta {
  glob<T>(pattern: string, options: { eager: true; import: "default" }): Record<string, T>;
}
