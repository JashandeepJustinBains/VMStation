/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        lake: {
          50: '#f0fdf4',
          100: '#dcfce7',
          200: '#bbf7d0',
          300: '#86efac',
          400: '#4ade80',
          500: '#22d3ee',
          600: '#06b6d4',
          700: '#0891b2',
          800: '#0e7490',
          900: '#164e63',
        },
        cluster: {
          control: '#8b5cf6',
          worker: '#06b6d4',
          storage: '#f59e0b',
          network: '#10b981',
          monitor: '#ef4444',
        }
      },
      backgroundImage: {
        'lake-gradient': 'radial-gradient(ellipse at center, rgba(34, 211, 238, 0.1) 0%, rgba(6, 182, 212, 0.05) 50%, rgba(8, 145, 178, 0.02) 100%)',
        'water-ripple': 'radial-gradient(circle at 30% 40%, rgba(34, 211, 238, 0.3), transparent 50%), radial-gradient(circle at 80% 20%, rgba(6, 182, 212, 0.2), transparent 50%)'
      },
      animation: {
        'float': 'float 6s ease-in-out infinite',
        'ripple': 'ripple 2s ease-out',
        'rope-flow': 'rope-flow 3s ease-in-out infinite',
        'barber-pole': 'barber-pole 2s linear infinite',
        'water-shimmer': 'water-shimmer 4s ease-in-out infinite'
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-10px)' }
        },
        ripple: {
          '0%': { transform: 'scale(0)', opacity: '1' },
          '100%': { transform: 'scale(4)', opacity: '0' }
        },
        'rope-flow': {
          '0%, 100%': { strokeDashoffset: '0' },
          '50%': { strokeDashoffset: '10' }
        },
        'barber-pole': {
          '0%': { strokeDashoffset: '0' },
          '100%': { strokeDashoffset: '20' }
        },
        'water-shimmer': {
          '0%, 100%': { opacity: '0.1' },
          '50%': { opacity: '0.3' }
        }
      }
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
  ],
}