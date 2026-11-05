import js from '@eslint/js'
import pluginVue from 'eslint-plugin-vue'
import globals from 'globals'

export default [
  { ignores: ['dist/**', 'node_modules/**', 'coverage/**'] },
  js.configs.recommended,
  ...pluginVue.configs['flat/recommended'],
  {
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: { ...globals.browser },
    },
    rules: {
      // Every visible text comes from src/i18n/locales (French and Malagasy).
      'vue/no-bare-strings-in-template': [
        'error',
        { allowlist: ['(', ')', ',', '.', ':', '-', '–', '—', '#', '%', '+', '++', '+++', '<', '>', '|', '/', '·'] },
      ],
      'vue/max-attributes-per-line': 'off',
      'vue/singleline-html-element-content-newline': 'off',
      'vue/html-self-closing': 'off',
      'vue/multi-word-component-names': 'off',
      'vue/html-closing-bracket-newline': 'off',
      'vue/multiline-html-element-content-newline': 'off',
      'vue/html-indent': 'off',
    },
  },
  {
    files: ['vite.config.js', 'eslint.config.js', 'tests/**/*.js'],
    languageOptions: { globals: { ...globals.node } },
  },
]
