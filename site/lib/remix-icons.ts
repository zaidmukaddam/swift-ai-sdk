import { createElement, type ComponentType } from 'react';
import {
  RiRobot2Line,
  RiToolsLine,
  RiChat3Line,
  RiHistoryLine,
  RiBrainLine,
  RiCpuLine,
  RiBookOpenLine,
  RiPlugLine,
  RiTableLine,
  RiBubbleChartLine,
  RiFlaskLine,
  RiSparklingLine,
  RiPulseLine,
  RiGalleryLine,
  RiRocketLine,
  RiRoadMapLine,
  RiImageLine,
  RiSettings3Line,
  RiVoiceprintLine,
  RiBracesLine,
  RiText,
} from '@remixicon/react';

const registry: Record<string, ComponentType> = {
  BookOpen: RiBookOpenLine,
  Rocket: RiRocketLine,
  Sparkles: RiSparklingLine,
  Map: RiRoadMapLine,
  Type: RiText,
  Images: RiGalleryLine,
  Braces: RiBracesLine,
  Wrench: RiToolsLine,
  Bot: RiRobot2Line,
  Brain: RiBrainLine,
  Cable: RiPlugLine,
  Cpu: RiCpuLine,
  MessageSquare: RiChat3Line,
  Waves: RiPulseLine,
  AudioWaveform: RiVoiceprintLine,
  Network: RiBubbleChartLine,
  Image: RiImageLine,
  Settings: RiSettings3Line,
  FlaskConical: RiFlaskLine,
  History: RiHistoryLine,
  Table: RiTableLine,
};

function replaceIcon<T extends { icon?: unknown }>(node: T): T {
  if (typeof node.icon === 'string') {
    const Icon = registry[node.icon];
    if (!Icon) console.warn(`[remix-icons] Unknown icon: ${node.icon}`);
    node.icon = Icon ? createElement(Icon) : undefined;
  }
  return node;
}

export function remixIconsPlugin() {
  return {
    name: 'remix:icon',
    transformPageTree: {
      file: replaceIcon,
      folder: replaceIcon,
      separator: replaceIcon,
    },
  };
}
