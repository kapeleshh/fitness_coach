"""
Garmin Data Parser - Parses exported Garmin Connect data
Combines sleep, stress, body battery, HRV, and activity data into unified daily records
"""

import json
import os
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
from pathlib import Path

@dataclass
class DailyHealthData:
    """Combined daily health metrics from Garmin"""
    date: str
    
    # Sleep
    sleep_score: int = 0
    deep_sleep_minutes: int = 0
    light_sleep_minutes: int = 0
    rem_sleep_minutes: int = 0
    awake_minutes: int = 0
    sleep_start_time: Optional[str] = None
    sleep_end_time: Optional[str] = None
    avg_sleep_stress: float = 0.0
    sleep_insight: str = ""
    sleep_feedback: str = ""
    
    # Heart Rate & HRV
    resting_hr: int = 0
    min_hr: int = 0
    max_hr: int = 0
    hrv: float = 0.0
    hrv_status: str = "UNKNOWN"
    
    # Body Battery
    body_battery_start: int = 0
    body_battery_end: int = 0
    body_battery_high: int = 0
    body_battery_low: int = 0
    body_battery_charged: int = 0
    body_battery_drained: int = 0
    
    # Stress
    avg_stress: int = 0
    max_stress: int = 0
    stress_rest_minutes: int = 0
    stress_low_minutes: int = 0
    stress_medium_minutes: int = 0
    stress_high_minutes: int = 0
    
    # Activity
    steps: int = 0
    distance_meters: float = 0.0
    active_calories: int = 0
    total_calories: int = 0
    floors_climbed: int = 0
    active_minutes: int = 0
    
    # Respiration
    avg_respiration: float = 0.0
    lowest_respiration: float = 0.0
    highest_respiration: float = 0.0


class GarminDataParser:
    """Parser for Garmin Connect exported data"""
    
    def __init__(self, data_dir: str):
        self.data_dir = Path(data_dir)
        self.daily_data: Dict[str, DailyHealthData] = {}
        
    def find_data_folder(self) -> Optional[Path]:
        """Find the Garmin data folder with the UUID"""
        for item in self.data_dir.iterdir():
            if item.is_dir() and len(item.name) > 30:
                di_connect = item / "DI_CONNECT"
                if di_connect.exists():
                    return item
        return None
    
    def parse_all(self) -> List[DailyHealthData]:
        """Parse all available Garmin data files"""
        data_folder = self.find_data_folder()
        if not data_folder:
            print("Could not find Garmin data folder")
            return []
        
        # Parse each data source
        self._parse_sleep_data(data_folder)
        self._parse_health_status(data_folder)
        self._parse_uds_data(data_folder)
        self._parse_activities(data_folder)
        
        # Sort by date and return
        sorted_dates = sorted(self.daily_data.keys(), reverse=True)
        return [self.daily_data[d] for d in sorted_dates]
    
    def _get_or_create_day(self, date_str: str) -> DailyHealthData:
        """Get existing day data or create new"""
        if date_str not in self.daily_data:
            self.daily_data[date_str] = DailyHealthData(date=date_str)
        return self.daily_data[date_str]
    
    def _parse_sleep_data(self, data_folder: Path):
        """Parse sleep data from DI-Connect-Wellness"""
        wellness_dir = data_folder / "DI_CONNECT" / "DI-Connect-Wellness"
        
        for file in wellness_dir.glob("*_sleepData.json"):
            with open(file, 'r', encoding='utf-8') as f:
                sleep_records = json.load(f)
            
            for record in sleep_records:
                if not isinstance(record, dict) or 'calendarDate' not in record:
                    continue
                
                date_str = record.get('calendarDate')
                day = self._get_or_create_day(date_str)
                
                # Sleep scores
                scores = record.get('sleepScores', {})
                day.sleep_score = scores.get('overallScore', 0)
                
                # Sleep stages (convert seconds to minutes)
                day.deep_sleep_minutes = record.get('deepSleepSeconds', 0) // 60
                day.light_sleep_minutes = record.get('lightSleepSeconds', 0) // 60
                day.rem_sleep_minutes = record.get('remSleepSeconds', 0) // 60
                day.awake_minutes = record.get('awakeSleepSeconds', 0) // 60
                
                # Sleep times
                day.sleep_start_time = record.get('sleepStartTimestampGMT')
                day.sleep_end_time = record.get('sleepEndTimestampGMT')
                
                # Sleep stress
                day.avg_sleep_stress = record.get('avgSleepStress', 0.0)
                
                # Insights
                day.sleep_insight = scores.get('insight', '')
                day.sleep_feedback = scores.get('feedback', '')
    
    def _parse_health_status(self, data_folder: Path):
        """Parse HRV and health status data"""
        wellness_dir = data_folder / "DI_CONNECT" / "DI-Connect-Wellness"
        
        for file in wellness_dir.glob("*_healthStatusData.json"):
            with open(file, 'r', encoding='utf-8') as f:
                health_records = json.load(f)
            
            for record in health_records:
                if not isinstance(record, dict) or 'calendarDate' not in record:
                    continue
                
                date_str = record.get('calendarDate')
                day = self._get_or_create_day(date_str)
                
                metrics = record.get('metrics', [])
                for metric in metrics:
                    metric_type = metric.get('type')
                    value = metric.get('value', 0)
                    status = metric.get('status', 'UNKNOWN')
                    
                    if metric_type == 'HRV':
                        day.hrv = float(value) if value else 0.0
                        day.hrv_status = status
                    elif metric_type == 'HR':
                        day.resting_hr = int(value) if value else 0
                    elif metric_type == 'RESPIRATION':
                        day.avg_respiration = float(value) if value else 0.0
    
    def _parse_uds_data(self, data_folder: Path):
        """Parse UDS (User Daily Summary) data - body battery, stress, steps"""
        aggregator_dir = data_folder / "DI_CONNECT" / "DI-Connect-Aggregator"
        
        for file in aggregator_dir.glob("UDSFile_*.json"):
            with open(file, 'r', encoding='utf-8') as f:
                uds_records = json.load(f)
            
            for record in uds_records:
                if not isinstance(record, dict) or 'calendarDate' not in record:
                    continue
                
                date_str = record.get('calendarDate')
                day = self._get_or_create_day(date_str)
                
                # Basic metrics
                day.steps = record.get('totalSteps', 0)
                day.distance_meters = record.get('wellnessDistanceMeters', 0.0)
                day.active_calories = int(record.get('activeKilocalories', 0))
                day.total_calories = int(record.get('totalKilocalories', 0))
                day.floors_climbed = int(record.get('floorsAscendedInMeters', 0) / 3)
                day.min_hr = record.get('minHeartRate', 0)
                day.max_hr = record.get('maxHeartRate', 0)
                day.resting_hr = record.get('restingHeartRate', day.resting_hr)
                
                # Active minutes
                moderate = record.get('moderateIntensityMinutes', 0)
                vigorous = record.get('vigorousIntensityMinutes', 0)
                day.active_minutes = moderate + (vigorous * 2)  # Double count vigorous
                
                # Body Battery
                bb = record.get('bodyBattery', {})
                if bb:
                    day.body_battery_charged = bb.get('chargedValue', 0)
                    day.body_battery_drained = bb.get('drainedValue', 0)
                    
                    for stat in bb.get('bodyBatteryStatList', []):
                        stat_type = stat.get('bodyBatteryStatType')
                        value = stat.get('statsValue', 0)
                        
                        if stat_type == 'STARTOFDAY':
                            day.body_battery_start = value
                        elif stat_type == 'MOSTRECENT':
                            day.body_battery_end = value
                        elif stat_type == 'HIGHEST':
                            day.body_battery_high = value
                        elif stat_type == 'LOWEST':
                            day.body_battery_low = value
                
                # Stress
                stress = record.get('allDayStress', {})
                if stress:
                    for agg in stress.get('aggregatorList', []):
                        if agg.get('type') == 'TOTAL':
                            day.avg_stress = agg.get('averageStressLevel', 0)
                            day.max_stress = agg.get('maxStressLevel', 0)
                            day.stress_rest_minutes = agg.get('restDuration', 0) // 60
                            day.stress_low_minutes = agg.get('lowDuration', 0) // 60
                            day.stress_medium_minutes = agg.get('mediumDuration', 0) // 60
                            day.stress_high_minutes = agg.get('highDuration', 0) // 60
                            break
                
                # Respiration
                resp = record.get('respiration', {})
                if resp:
                    day.avg_respiration = resp.get('avgWakingRespirationValue', 0.0)
                    day.lowest_respiration = resp.get('lowestRespirationValue', 0.0)
                    day.highest_respiration = resp.get('highestRespirationValue', 0.0)
    
    def _parse_activities(self, data_folder: Path):
        """Parse workout/activity data"""
        fitness_dir = data_folder / "DI_CONNECT" / "DI-Connect-Fitness"
        
        for file in fitness_dir.glob("*_summarizedActivities.json"):
            with open(file, 'r', encoding='utf-8') as f:
                activities = json.load(f)
            
            # Activities is usually a dict with activity list
            activity_list = activities if isinstance(activities, list) else activities.get('summarizedActivitiesExport', [])
            
            for activity in activity_list:
                if not isinstance(activity, dict):
                    continue
                    
                # Extract date from start time
                start_time = activity.get('startTimeLocal', activity.get('beginTimestamp'))
                if start_time:
                    if isinstance(start_time, str):
                        date_str = start_time[:10]
                    else:
                        # Timestamp in milliseconds
                        dt = datetime.fromtimestamp(start_time / 1000)
                        date_str = dt.strftime('%Y-%m-%d')
                    
                    # Mark this day as having workout
                    # Could add more workout details here
    
    def to_json(self) -> str:
        """Export all data as JSON"""
        sorted_dates = sorted(self.daily_data.keys(), reverse=True)
        data_list = [asdict(self.daily_data[d]) for d in sorted_dates]
        return json.dumps(data_list, indent=2)
    
    def save_to_file(self, output_path: str):
        """Save parsed data to JSON file"""
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(self.to_json())
        print(f"Saved {len(self.daily_data)} days of data to {output_path}")


def main():
    """Main function to parse Garmin data"""
    # Get the data directory
    script_dir = Path(__file__).parent.parent
    data_dir = script_dir / "data"
    
    if not data_dir.exists():
        print(f"Data directory not found: {data_dir}")
        return
    
    # Parse all data
    parser = GarminDataParser(str(data_dir))
    data = parser.parse_all()
    
    print(f"\n📊 Parsed {len(data)} days of health data")
    
    if data:
        # Show sample of recent data
        print("\n🔍 Recent Data Sample:")
        for day in data[:5]:
            print(f"\n📅 {day.date}:")
            print(f"   💤 Sleep: {day.sleep_score} | Deep: {day.deep_sleep_minutes}min | REM: {day.rem_sleep_minutes}min")
            print(f"   💚 Body Battery: {day.body_battery_start}→{day.body_battery_end} | High: {day.body_battery_high}")
            print(f"   😰 Stress: avg {day.avg_stress} | Low: {day.stress_low_minutes}min | High: {day.stress_high_minutes}min")
            print(f"   ❤️ HRV: {day.hrv}ms | Resting HR: {day.resting_hr}bpm")
            print(f"   🚶 Steps: {day.steps:,} | Calories: {day.total_calories:,}")
    
    # Save to file
    output_path = script_dir / "backend" / "parsed_health_data.json"
    parser.save_to_file(str(output_path))


if __name__ == "__main__":
    main()
