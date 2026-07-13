'use client';

import { Fragment, useState } from 'react';
import { RiCheckLine, RiFileCopyLine } from '@remixicon/react';
import { cn } from '@/lib/cn';

type Tab = 'skill' | 'llms';

const tabs: {
  id: Tab;
  label: string;
  prompt?: string;
  command: string;
}[] = [
  {
    id: 'skill',
    label: 'Skill',
    prompt: '$',
    command: 'npx skills add zaidmukaddam/swift-ai-sdk',
  },
  {
    id: 'llms',
    label: 'llms.txt',
    command: 'https://swift-ai-sdk.dev/llms.txt',
  },
];

export function HeroInstall() {
  const [active, setActive] = useState<Tab>('skill');
  const [copied, setCopied] = useState(false);
  const tab = tabs.find((t) => t.id === active) ?? tabs[0];

  return (
    <div className="flex flex-col items-center gap-4">
      <div role="tablist" aria-label="For agents" className="flex items-center gap-3 text-sm">
        {tabs.map((t, i) => (
          <Fragment key={t.id}>
            {i > 0 && <span aria-hidden="true" className="h-4 w-px bg-fd-border" />}
            <button
              type="button"
              role="tab"
              aria-selected={active === t.id}
              onClick={() => {
                setActive(t.id);
                setCopied(false);
              }}
              className={cn(
                'select-none rounded-sm px-1 py-2 font-medium transition-colors duration-150 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[oklch(0.65_0.199_31.6)]',
                active === t.id
                  ? 'text-fd-foreground'
                  : 'text-fd-muted-foreground hover:text-fd-foreground',
              )}
            >
              {t.label}
            </button>
          </Fragment>
        ))}
      </div>

      <button
        type="button"
        aria-label={`Copy: ${tab.command}`}
        onClick={() => {
          void navigator.clipboard.writeText(tab.command).then(() => {
            setCopied(true);
            setTimeout(() => setCopied(false), 1500);
          });
        }}
        className="card-surface group flex h-12 max-w-full items-center gap-3 rounded-full bg-fd-card/60 pl-5 pr-4 font-mono text-[13px] transition-[scale] duration-150 ease-(--ease-out-strong) active:scale-[0.96] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[oklch(0.65_0.199_31.6)]"
      >
        <span className="flex min-w-0 items-center gap-2">
          {tab.prompt ? (
            <span className="shrink-0 select-none text-fd-muted-foreground/60">
              {tab.prompt}
            </span>
          ) : null}
          <span className="truncate text-fd-foreground">{tab.command}</span>
        </span>
        <span className="relative grid size-4 shrink-0 place-items-center text-fd-muted-foreground transition-colors duration-150 group-hover:text-fd-foreground">
          <RiFileCopyLine
            aria-hidden="true"
            className={cn(
              'col-start-1 row-start-1 size-3.5 transition-[opacity,scale] duration-150 ease-[cubic-bezier(0.2,0,0,1)]',
              copied ? 'scale-50 opacity-0' : 'scale-100 opacity-100',
            )}
          />
          <RiCheckLine
            aria-hidden="true"
            className={cn(
              'col-start-1 row-start-1 size-3.5 text-[oklch(0.65_0.199_31.6)] transition-[opacity,scale] duration-150 ease-[cubic-bezier(0.2,0,0,1)]',
              copied ? 'scale-100 opacity-100' : 'scale-50 opacity-0',
            )}
          />
        </span>
      </button>
    </div>
  );
}
