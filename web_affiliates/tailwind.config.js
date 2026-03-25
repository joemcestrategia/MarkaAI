/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          light: '#7C3AED',
          DEFAULT: '#6D28D9',
          dark: '#5B21B6',
        },
      },
    },
  },
  plugins: [],
}
