'use client';

import { useEffect, useState } from 'react';

interface SyntaxHighlighterProps {
  code: string;
  language: string;
}

export default function SyntaxHighlighter({ code, language }: SyntaxHighlighterProps) {
  const [highlightedCode, setHighlightedCode] = useState<string>('');

  useEffect(() => {
    // Simple syntax highlighting - in a real app you'd use shiki or prism
    const highlighted = basicHighlight(code, language);
    setHighlightedCode(highlighted);
  }, [code, language]);

  const basicHighlight = (code: string, lang: string): string => {
    if (lang === 'bash') {
      return code
        .replace(/(#.*)/g, '<span style="color: #6B7280;">$1</span>')
        .replace(/\b(echo|if|then|else|fi|for|while|do|done|function|return|exit|set)\b/g, '<span style="color: #8B5CF6;">$1</span>')
        .replace(/\$\w+/g, '<span style="color: #10B981;">$&</span>')
        .replace(/"([^"]*)"/g, '<span style="color: #F59E0B;">"$1"</span>');
    }
    
    if (lang === 'yaml') {
      return code
        .replace(/^(\s*\w+):/gm, '<span style="color: #3B82F6;">$1</span>:')
        .replace(/:\s*(.+)/g, ': <span style="color: #10B981;">$1</span>')
        .replace(/(#.*)/g, '<span style="color: #6B7280;">$1</span>');
    }
    
    if (lang === 'markdown') {
      return code
        .replace(/^(#{1,6})\s+(.+)/gm, '<span style="color: #8B5CF6;">$1</span> <span style="color: #F59E0B;">$2</span>')
        .replace(/\*\*(.*?)\*\*/g, '<span style="color: #EF4444; font-weight: bold;">$1</span>')
        .replace(/`([^`]+)`/g, '<span style="color: #10B981; background: rgba(16, 185, 129, 0.1); padding: 2px 4px; border-radius: 4px;">$1</span>');
    }
    
    return code;
  };

  const lines = code.split('\n');

  return (
    <div className="bg-black/20 text-sm font-mono overflow-auto">
      <div className="flex">
        {/* Line numbers */}
        <div className="flex-shrink-0 px-3 py-4 text-gray-500 text-right border-r border-white/10 select-none">
          {lines.map((_, index) => (
            <div key={index} className="leading-6">
              {index + 1}
            </div>
          ))}
        </div>
        
        {/* Code content */}
        <div className="flex-1 px-4 py-4 overflow-x-auto">
          {highlightedCode ? (
            <div 
              className="text-gray-100 leading-6 whitespace-pre"
              dangerouslySetInnerHTML={{ __html: highlightedCode }}
            />
          ) : (
            <div className="text-gray-100 leading-6 whitespace-pre">
              {code}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}