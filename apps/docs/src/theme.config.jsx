import { useRouter } from 'next/router'

export default {
  logo: <span>KeyHippo Documentation</span>,
  useNextSeoProps() {
    const { asPath } = useRouter()
    if (asPath !== '/docs') {
      return {
        titleTemplate: '%s – KeyHippo Docs'
      }
    } else {
      return {
        titleTemplate: 'KeyHippo Docs'
      }
    }
  },
  head: (
    <>
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <meta property="og:title" content="KeyHippo Documentation" />
      <meta
        property="og:description"
        content="Documentation for KeyHippo, an API key management solution for Supabase that extends Row Level Security (RLS) to seamlessly integrate API key authentication within existing security policies."
      />
      <meta name="robots" content="noindex, nofollow" />
      <link
        rel="icon"
        type="image/x-icon"
        href="https://avatars.githubusercontent.com/u/107670980?s=200&v=4"
      />
    </>
  ),
  project: {
    link: 'https://github.com/integrated-reasoning/KeyHippo'
  },
  editLink: {
    component: null
  },
  feedback: {
    content: null
  },
  footer: {
    text: (
      <span>
        Made by{' '}
        <a href="https://twitter.com/IntegrateReason" target="_blank">
          Integrated Reasoning, Inc. - say hello!
        </a>
      </span>
    )
  }
}
