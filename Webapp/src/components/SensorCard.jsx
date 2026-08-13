import React from 'react';

const SensorCard = ({ title, value, unit, icon, color }) => {
  return (
    <div className={`p-4 rounded-xl shadow-lg flex items-center justify-between transition-transform hover:scale-105`} style={{ backgroundColor: '#1a1a2e' }}>
      <div className="flex flex-col">
        <span className="text-gray-400 text-sm uppercase tracking-wider mb-1">{title}</span>
        <div className="flex items-baseline">
          <span className="text-2xl font-bold text-white mr-1">{value !== undefined ? value : '--'}</span>
          <span className="text-gray-400 text-sm">{unit}</span>
        </div>
      </div>
      <div className={`p-3 rounded-full text-2xl ${color} bg-opacity-20`}>
        {icon}
      </div>
    </div>
  );
};

export default SensorCard;
