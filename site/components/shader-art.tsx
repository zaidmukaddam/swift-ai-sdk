'use client';

import {
  Dithering,
  DotOrbit,
  GodRays,
  NeuroNoise,
  Waves,
} from '@paper-design/shaders-react';
import { useEffect, useState } from 'react';

export const swiftOrange = '#F05138';
const swiftCoral = '#FA7343';
const swiftAmber = '#FFB340';

function usePrefersReducedMotion() {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const query = window.matchMedia('(prefers-reduced-motion: reduce)');
    setReduced(query.matches);
    const onChange = (event: MediaQueryListEvent) => setReduced(event.matches);
    query.addEventListener('change', onChange);
    return () => query.removeEventListener('change', onChange);
  }, []);
  return reduced;
}

export function HeroBackdrop() {
  const reduced = usePrefersReducedMotion();

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 -z-10 mask-[radial-gradient(ellipse_75%_55%_at_50%_0%,black,transparent)]"
    >
      <Dithering
        colorBack="rgba(0, 0, 0, 0)"
        colorFront="rgba(240, 81, 56, 0.55)"
        shape="simplex"
        type="4x4"
        size={2.5}
        speed={reduced ? 0 : 0.25}
        scale={0.8}
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
}

export function WaveArt() {
  return (
    <div
      aria-hidden="true"
      className="h-20 w-full overflow-hidden rounded-lg border border-fd-border sm:h-24"
    >
      <Waves
        colorBack="rgba(0, 0, 0, 0)"
        colorFront="rgba(240, 81, 56, 0.8)"
        shape={1}
        amplitude={0.6}
        frequency={0.6}
        spacing={0.75}
        proportion={0.35}
        softness={0}
        scale={0.6}
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
}

export function StatArt() {
  const reduced = usePrefersReducedMotion();

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 opacity-60 mask-[radial-gradient(ellipse_90%_80%_at_100%_100%,black,transparent)]"
    >
      <Dithering
        colorBack="rgba(0, 0, 0, 0)"
        colorFront="rgba(240, 81, 56, 0.55)"
        shape="wave"
        type="4x4"
        size={2}
        speed={reduced ? 0 : 0.2}
        scale={0.7}
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
}

export function OnDeviceBackdrop() {
  const reduced = usePrefersReducedMotion();

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 -z-10 opacity-45 mask-[radial-gradient(ellipse_65%_65%_at_50%_45%,black,transparent)]"
    >
      <NeuroNoise
        colorBack="rgba(0, 0, 0, 0)"
        colorMid="rgba(240, 81, 56, 0.3)"
        colorFront="rgba(250, 115, 67, 0.8)"
        brightness={0.05}
        contrast={0.85}
        scale={0.7}
        speed={reduced ? 0 : 0.25}
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
}

export function OrbitArt() {
  const reduced = usePrefersReducedMotion();

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 opacity-45 mask-[radial-gradient(ellipse_70%_90%_at_100%_0%,black,transparent)]"
    >
      <DotOrbit
        colorBack="rgba(0, 0, 0, 0)"
        colors={[swiftOrange, swiftCoral, swiftAmber]}
        size={0.12}
        sizeRange={0.4}
        spreading={0.6}
        speed={reduced ? 0 : 0.3}
        scale={0.55}
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
}

export function StatementBackdrop() {
  const reduced = usePrefersReducedMotion();

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 -z-10 opacity-60 mask-[radial-gradient(ellipse_70%_100%_at_50%_50%,black,transparent)]"
    >
      <Dithering
        colorBack="rgba(0, 0, 0, 0)"
        colorFront="rgba(240, 81, 56, 0.4)"
        shape="ripple"
        type="4x4"
        size={2.5}
        speed={reduced ? 0 : 0.2}
        scale={0.9}
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
}

export function DocsBackdrop() {
  const reduced = usePrefersReducedMotion();

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-104 mask-[radial-gradient(ellipse_80%_100%_at_50%_-15%,black,transparent)]"
    >
      <Dithering
        colorBack="rgba(0, 0, 0, 0)"
        colorFront="rgba(240, 81, 56, 0.3)"
        shape="simplex"
        type="4x4"
        size={2.5}
        speed={reduced ? 0 : 0.2}
        scale={0.8}
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
}

export function AIPanelBackdrop() {
  const reduced = usePrefersReducedMotion();

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-40 opacity-70 mask-[linear-gradient(to_bottom,black,transparent)]"
    >
      <Dithering
        colorBack="rgba(0, 0, 0, 0)"
        colorFront="rgba(240, 81, 56, 0.28)"
        shape="simplex"
        type="4x4"
        size={2.5}
        speed={reduced ? 0 : 0.18}
        scale={0.8}
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
}

export function ClosingBackdrop() {
  const reduced = usePrefersReducedMotion();

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-0 -z-10 opacity-70 mask-[linear-gradient(to_top,black_35%,transparent_85%)]"
    >
      <GodRays
        colorBack="rgba(0, 0, 0, 0)"
        colorBloom="rgba(240, 81, 56, 0.5)"
        colors={[swiftOrange, swiftCoral, swiftAmber]}
        offsetY={1}
        density={0.35}
        intensity={0.5}
        spotty={0.35}
        midSize={0.1}
        midIntensity={0.4}
        bloom={0.5}
        speed={reduced ? 0 : 0.35}
        style={{ width: '100%', height: '100%' }}
      />
    </div>
  );
}
