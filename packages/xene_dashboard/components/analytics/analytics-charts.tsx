'use client'

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  LineChart,
  Line,
  PieChart,
  Pie,
  Cell,
} from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

const PLATFORM_COLORS: Record<string, string> = {
  soundcloud: '#ff5500',
  youtube: '#ff0000',
  bandcamp: '#1da0c3',
  unknown: '#666',
}

interface Props {
  topArtists: { name: string; count: number }[]
  platformData: { name: string; count: number }[]
  playsPerDay: { date: string; plays: number }[]
}

export function AnalyticsCharts({ topArtists, platformData, playsPerDay }: Props) {
  return (
    <div className="space-y-6">
      {/* Plays per day */}
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium">Plays per Day (last 14d)</CardTitle>
        </CardHeader>
        <CardContent>
          <ResponsiveContainer width="100%" height={200}>
            <LineChart data={playsPerDay}>
              <XAxis
                dataKey="date"
                tick={{ fontSize: 11, fill: '#888' }}
                axisLine={false}
                tickLine={false}
              />
              <YAxis
                tick={{ fontSize: 11, fill: '#888' }}
                axisLine={false}
                tickLine={false}
                width={24}
              />
              <Tooltip
                contentStyle={{
                  backgroundColor: '#1a1a1a',
                  border: '1px solid #333',
                  borderRadius: 6,
                  fontSize: 12,
                }}
              />
              <Line
                type="monotone"
                dataKey="plays"
                stroke="#a855f7"
                strokeWidth={2}
                dot={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>

      <div className="grid grid-cols-2 gap-6">
        {/* Top artists */}
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">Top Artists (30d)</CardTitle>
          </CardHeader>
          <CardContent>
            {topArtists.length === 0 ? (
              <p className="text-xs text-muted-foreground">No play history yet.</p>
            ) : (
              <ResponsiveContainer width="100%" height={240}>
                <BarChart
                  data={topArtists}
                  layout="vertical"
                  margin={{ left: 8, right: 8 }}
                >
                  <XAxis
                    type="number"
                    tick={{ fontSize: 10, fill: '#888' }}
                    axisLine={false}
                    tickLine={false}
                  />
                  <YAxis
                    type="category"
                    dataKey="name"
                    tick={{ fontSize: 10, fill: '#ccc' }}
                    axisLine={false}
                    tickLine={false}
                    width={90}
                  />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: '#1a1a1a',
                      border: '1px solid #333',
                      borderRadius: 6,
                      fontSize: 11,
                    }}
                  />
                  <Bar dataKey="count" fill="#a855f7" radius={[0, 3, 3, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>

        {/* Platform breakdown */}
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">Feed Items by Platform (30d)</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col items-center">
            {platformData.length === 0 ? (
              <p className="text-xs text-muted-foreground">No feed items yet.</p>
            ) : (
              <>
                <ResponsiveContainer width="100%" height={180}>
                  <PieChart>
                    <Pie
                      data={platformData}
                      dataKey="count"
                      nameKey="name"
                      cx="50%"
                      cy="50%"
                      outerRadius={70}
                    >
                      {platformData.map((entry) => (
                        <Cell
                          key={entry.name}
                          fill={PLATFORM_COLORS[entry.name] ?? '#666'}
                        />
                      ))}
                    </Pie>
                    <Tooltip
                      contentStyle={{
                        backgroundColor: '#1a1a1a',
                        border: '1px solid #333',
                        borderRadius: 6,
                        fontSize: 11,
                      }}
                    />
                  </PieChart>
                </ResponsiveContainer>
                <div className="flex gap-4 mt-2">
                  {platformData.map((p) => (
                    <div key={p.name} className="flex items-center gap-1.5">
                      <div
                        className="h-2.5 w-2.5 rounded-full"
                        style={{
                          backgroundColor:
                            PLATFORM_COLORS[p.name] ?? '#666',
                        }}
                      />
                      <span className="text-xs text-muted-foreground capitalize">
                        {p.name} ({p.count})
                      </span>
                    </div>
                  ))}
                </div>
              </>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
