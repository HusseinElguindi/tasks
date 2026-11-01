// What the Worker tests import through Vite.
declare module "*?raw" {
  const text: string;
  export default text;
}
