import Link from 'next/link';
import type { ReactNode } from 'react';
import { RiArrowRightSLine } from '@remixicon/react';
import { gitConfig } from '@/lib/shared';
import { BrandMark } from '@/components/logo';
import { HeroInstall } from '@/components/hero-install';
import {
  ClosingBackdrop,
  HeroBackdrop,
  OnDeviceBackdrop,
  OrbitArt,
  StatArt,
  StatementBackdrop,
  WaveArt,
} from '@/components/shader-art';

const githubUrl = `https://github.com/${gitConfig.user}/${gitConfig.repo}`;

const pillButton =
  'inline-flex h-12 select-none items-center rounded-full bg-[oklch(0.65_0.199_31.6)] px-7 text-[15px] font-medium text-white transition-[scale,opacity] duration-150 ease-(--ease-out-strong) hover:opacity-90 active:scale-[0.96] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[oklch(0.65_0.199_31.6)]';

const textLink =
  'group inline-flex select-none items-center gap-0.5 py-2.5 text-[15px] font-medium text-[oklch(0.65_0.199_31.6)] transition-colors duration-150 hover:text-[oklch(0.552_0.185_32.1)] dark:hover:text-[oklch(0.709_0.177_39.5)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[oklch(0.65_0.199_31.6)] rounded-sm';

const linkChevron =
  'size-4 transition-[translate] duration-150 ease-(--ease-out-strong) group-hover:translate-x-0.5';

export default function HomePage() {
  return (
    <div className="flex flex-col flex-1">
      <Hero />
      <Bento />
      <WireStatement />
      <OnDevice />
      <FinalCta />
    </div>
  );
}

function Hero() {
  return (
    <section className="relative overflow-hidden">
      <HeroBackdrop />
      <div className="mx-auto flex w-full max-w-4xl flex-col items-center px-6 pt-28 pb-16 text-center">
      <p className="hero-enter hero-enter-1 text-sm">
        <BrandMark />
      </p>
      <h1 className="hero-enter hero-enter-2 mt-4 text-balance text-5xl font-semibold leading-[1.02] tracking-[-0.02em] sm:text-7xl">
        Put AI in your app
        <br />
        <span className="text-fd-muted-foreground">by tonight.</span>
      </h1>
      <p className="hero-enter hero-enter-3 mt-6 max-w-xl text-pretty text-lg leading-relaxed text-fd-muted-foreground">
        Streaming chat, agents that call your code, live voice, and models
        that run on the phone itself. One package for iOS and macOS.
      </p>
      <div className="hero-enter hero-enter-4 mt-8 flex flex-wrap items-center justify-center gap-6">
        <Link href="/docs" className={pillButton}>
          Get Started
        </Link>
        <a href={githubUrl} rel="noreferrer noopener" className={textLink}>
          View on GitHub
          <RiArrowRightSLine aria-hidden="true" className={linkChevron} />
        </a>
      </div>
      <div className="hero-enter hero-enter-5 mt-12 w-full">
        <HeroInstall />
      </div>
        <HeroCode />
      </div>
    </section>
  );
}

function HeroCode() {
  return (
    <div className="hero-enter hero-enter-6 mt-16 w-full max-w-xl text-left">
      <div className="mb-3 font-mono text-xs text-fd-muted-foreground">
        Weather.swift
      </div>
      <pre className="card-surface overflow-x-auto rounded-xl bg-fd-card/50 p-6 font-mono text-[13px] leading-[1.7]">
        <code>
          <Kw>import</Kw> AI{'\n\n'}
          <Kw>let</Kw> result = streamText({'\n'}
          {'  '}model: AnthropicModel(<Str>&quot;claude-sonnet-5&quot;</Str>),{'\n'}
          {'  '}prompt: <Str>&quot;Weather in Mumbai?&quot;</Str>,{'\n'}
          {'  '}tools: [weatherTool],{'\n'}
          {'  '}reasoning: .medium{'\n'}
          ){'\n\n'}
          <Kw>for try await</Kw> token <Kw>in</Kw> result.textStream {'{'}
          {'\n'}
          {'  '}print(token, terminator: <Str>&quot;&quot;</Str>){'\n'}
          {'}'}
        </code>
      </pre>
    </div>
  );
}

function Kw({ children }: { children: ReactNode }) {
  return (
    <span className="text-[oklch(0.65_0.199_31.6)] dark:text-[oklch(0.709_0.177_39.5)]">
      {children}
    </span>
  );
}

function Ty({ children }: { children: ReactNode }) {
  return <span className="text-fd-foreground">{children}</span>;
}

function Str({ children }: { children: ReactNode }) {
  return <span className="text-fd-muted-foreground">{children}</span>;
}

const tile = 'card-surface flex min-w-0 flex-col rounded-[2rem] bg-fd-card p-6';

function Bento() {
  return (
    <section className="mx-auto w-full max-w-6xl px-6 py-24">
      <h2 className="text-balance text-center text-4xl font-semibold tracking-[-0.02em] sm:text-5xl">
        Everything you need.
        <br />
        <span className="text-fd-muted-foreground">
          Nothing to glue together.
        </span>
      </h2>
      <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <ProvidersTile />
        <TestsTile />
        <SchemaTile />
        <ChatTile />
        <RealtimeTile />
      </div>
    </section>
  );
}

type ProviderLogo = { name: string; src: string; dark?: string; invertOnDark?: boolean };

const providerLogos: ProviderLogo[] = [
  { name: 'OpenAI', src: '/logos/openai.svg', dark: '/logos/openai-dark.svg' },
  { name: 'Anthropic', src: '/logos/anthropic.svg', dark: '/logos/anthropic-dark.svg' },
  { name: 'Google Gemini', src: '/logos/gemini.svg' },
  { name: 'xAI', src: '/logos/xai.svg', dark: '/logos/xai-dark.svg' },
  { name: 'Amazon Bedrock', src: '/logos/aws.svg', dark: '/logos/aws-dark.svg' },
  { name: 'Azure OpenAI', src: '/logos/azure.svg' },
  { name: 'Groq', src: '/logos/groq.svg' },
  { name: 'Mistral', src: '/logos/mistral.svg' },
  { name: 'DeepSeek', src: '/logos/deepseek.svg' },
  { name: 'Perplexity', src: '/logos/perplexity.svg' },
  { name: 'Cohere', src: '/logos/cohere.svg' },
  { name: 'Ollama', src: '/logos/ollama.svg', dark: '/logos/ollama-dark.svg' },
  { name: 'OpenRouter', src: '/logos/openrouter.svg', dark: '/logos/openrouter-dark.svg' },
  { name: 'Sarvam', src: '/logos/sarvam-logo.webp', invertOnDark: true },
];

function ProviderCell({ logo }: { logo: ProviderLogo }) {
  const img = 'h-6 w-auto max-w-12 object-contain';
  return (
    <li
      title={logo.name}
      className="flex h-12 items-center justify-center rounded-lg bg-fd-secondary/50"
    >
      {logo.dark ? (
        <>
          <img src={logo.src} alt={logo.name} className={`${img} dark:hidden`} />
          <img src={logo.dark} alt="" aria-hidden="true" className={`${img} hidden dark:block`} />
        </>
      ) : (
        <img
          src={logo.src}
          alt={logo.name}
          className={logo.invertOnDark ? `${img} dark:invert` : img}
        />
      )}
    </li>
  );
}

function ProvidersTile() {
  return (
    <div className={`${tile} relative overflow-hidden lg:col-span-2`}>
      <OrbitArt />
      <h3 className="relative text-xl font-semibold tracking-tight">
        Any model. One line to change your mind.
      </h3>
      <p className="relative mt-2 text-pretty text-sm leading-relaxed text-fd-muted-foreground">
        Claude, GPT, Gemini, Grok, or Ollama running on your Mac. Pick one
        today, swap it tomorrow, and nothing else in your code moves.
      </p>
      <ul className="relative mt-auto grid grid-cols-4 gap-2 pt-6 sm:grid-cols-7">
        {providerLogos.map((logo) => (
          <ProviderCell key={logo.name} logo={logo} />
        ))}
      </ul>
    </div>
  );
}

function TestsTile() {
  return (
    <div className={`${tile} relative flex flex-col justify-between gap-8 overflow-hidden`}>
      <StatArt />
      <h3 className="relative text-xl font-semibold tracking-tight">
        Works in airplane mode.
      </h3>
      <div className="relative">
        <div className="text-5xl font-semibold tracking-[-0.02em] text-[oklch(0.65_0.199_31.6)]">
          offline
        </div>
        <p className="mt-1 text-pretty text-sm text-fd-muted-foreground">
          Apple's on-device models answer through the same call as the cloud
          ones. No network, no key, no data leaving the phone.
        </p>
      </div>
    </div>
  );
}

function SchemaTile() {
  return (
    <div className={tile}>
      <h3 className="text-xl font-semibold tracking-tight">
        JSON you can actually trust.
      </h3>
      <p className="mt-2 text-pretty text-sm leading-relaxed text-fd-muted-foreground">
        Describe the shape, get typed Codable values back. Bad output turns
        into a thrown error, not a crash in your view code.
      </p>
      <div className="mt-auto pt-4">
        <pre className="overflow-x-auto rounded-lg border border-fd-border p-4 font-mono text-[11.5px] leading-[1.7] text-fd-muted-foreground">
          <code>
            Schema.object([{'\n'}
            {'  '}<Str>&quot;name&quot;</Str>: .string(),{'\n'}
            {'  '}<Str>&quot;pop&quot;</Str>: .integer(){'\n'}
            ])
          </code>
        </pre>
      </div>
    </div>
  );
}

function ChatTile() {
  return (
    <div className={`${tile} lg:col-span-2`}>
      <h3 className="text-xl font-semibold tracking-tight">
        A chat screen in an afternoon.
      </h3>
      <p className="mt-2 text-pretty text-sm leading-relaxed text-fd-muted-foreground">
        ChatSession holds the messages, streams the tokens, and talks to the
        same route your web app already uses. SwiftUI renders it.
      </p>
      <div className="mt-auto pt-4">
        <pre className="overflow-x-auto rounded-lg border border-fd-border p-4 font-mono text-[11.5px] leading-[1.7] text-fd-muted-foreground">
          <code>
            @State <Kw>var</Kw> chat = ChatSession({'\n'}
            {'  '}transport: HTTPChatTransport({'\n'}
            {'    '}api: chatRoute{'\n'}
            {'  '}){'\n'}
            ){'\n\n'}
            ForEach(chat.messages) {'{'}{'\n'}
            {'  '}Text($0.text){'\n'}
            {'}'}
          </code>
        </pre>
      </div>
    </div>
  );
}

function RealtimeTile() {
  return (
    <div className={`${tile} lg:col-span-2`}>
      <h3 className="text-xl font-semibold tracking-tight">
        Talk to it. It talks back.
      </h3>
      <p className="mt-2 max-w-md text-pretty text-sm leading-relaxed text-fd-muted-foreground">
        Live voice over WebSockets: the mic goes in, speech comes out, and
        your tools run in between. Interrupt it mid-sentence and it stops.
      </p>
      <div className="mt-auto pt-4">
        <WaveArt />
      </div>
    </div>
  );
}

function WireStatement() {
  return (
    <section className="relative overflow-hidden border-y border-fd-border bg-fd-card/40">
      <StatementBackdrop />
      <div className="mx-auto max-w-3xl px-6 py-28 text-center">
        <h2 className="text-balance text-4xl font-semibold leading-[1.05] tracking-[-0.02em] sm:text-5xl">
          Your backend won't
          <br />
          notice the difference.
        </h2>
        <p className="mx-auto mt-6 max-w-xl text-pretty text-lg leading-relaxed text-fd-muted-foreground">
          The app speaks the same streaming protocol your web frontend does,
          chunk for chunk. Keep the server you have. Add the app you've been
          meaning to build.
        </p>
        <Link href="/docs/streaming-protocol" className={`${textLink} mt-6`}>
          Read About the Protocol
          <RiArrowRightSLine aria-hidden="true" className={linkChevron} />
        </Link>
      </div>
    </section>
  );
}

function OnDevice() {
  return (
    <section className="relative mx-auto w-full max-w-4xl overflow-hidden px-6 py-28 text-center">
      <OnDeviceBackdrop />
      <p className="text-sm font-semibold text-[oklch(0.65_0.199_31.6)]">
        Only on iOS and macOS
      </p>
      <h2 className="mt-4 text-balance text-4xl font-semibold leading-[1.05] tracking-[-0.02em] sm:text-5xl">
        The model is already
        <br />
        <span className="text-fd-muted-foreground">in their pocket.</span>
      </h2>
      <p className="mx-auto mt-6 max-w-xl text-pretty text-lg leading-relaxed text-fd-muted-foreground">
        Apple Intelligence answers on the device itself: free, instant, and
        private. When it isn't available, fall back to the cloud with one
        line. Your feature code never knows which one ran.
      </p>
      <pre className="card-surface mx-auto mt-10 max-w-md overflow-x-auto rounded-xl bg-fd-card/50 p-5 text-left font-mono text-[13px] leading-[1.7]">
        <code>
          <Kw>let</Kw> model: <Kw>any</Kw> <Ty>LanguageModel</Ty> ={'\n'}
          {'  '}available ? <Ty>FoundationModelsModel</Ty>(){'\n'}
          {'  '}: <Ty>AnthropicModel</Ty>(<Str>&quot;claude-sonnet-5&quot;</Str>)
        </code>
      </pre>
    </section>
  );
}

function FinalCta() {
  return (
    <section className="relative overflow-hidden border-t border-fd-border">
      <ClosingBackdrop />
      <div className="mx-auto flex max-w-4xl flex-col items-center px-6 py-28 text-center">
        <h2 className="text-5xl font-semibold leading-[1.02] tracking-[-0.02em] sm:text-6xl">
          Ship it.
        </h2>
        <p className="mt-5 max-w-md text-pretty text-lg leading-relaxed text-fd-muted-foreground">
          Add the package, pick a model, send a message. If Ollama is
          running on your Mac, you don't even need an API key.
        </p>
        <div className="mt-9 flex flex-wrap items-center justify-center gap-6">
          <Link href="/docs/getting-started" className={pillButton}>
            Getting Started
          </Link>
          <Link href="/docs/guides" className={textLink}>
            Follow a Guide
            <RiArrowRightSLine aria-hidden="true" className={linkChevron} />
          </Link>
        </div>
        <p className="mt-20 text-xs text-fd-muted-foreground">
          Open source, MIT licensed.
        </p>
        <p className="mt-2 text-xs text-fd-muted-foreground">
          Building with an agent? Every docs page is raw markdown at{' '}
          <a
            href="/llms.txt"
            className="underline underline-offset-2 transition-colors duration-150 hover:text-fd-foreground"
          >
            /llms.txt
          </a>
          .
        </p>
      </div>
    </section>
  );
}
