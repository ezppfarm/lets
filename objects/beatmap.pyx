import time
import requests
import datetime
import re
import threading

from common import generalUtils
from common.log import logUtils as log
from constants import rankedStatuses
from helpers import osuapiHelper
from objects import glob
from common.constants.gameModes import getGameModeForDB

class beatmap:
	__slots__ = ["songName", "fileMD5", "rankedStatus", "rankedStatusFrozen", "beatmapID", "beatmapSetID", "offset",
	             "rating", "starsStd", "starsTaiko", "starsCtb", "starsMania", "AR", "OD", "maxCombo", "hitLength",
	             "bpm", "playcount" ,"passcount", "refresh"]

	def __init__(self, md5 = None, beatmapSetID = None, gameMode = 0, refresh=False):
		"""
		Initialize a beatmap object.
		md5 -- beatmap md5. Optional.
		beatmapSetID -- beatmapSetID. Optional.
		"""
		self.songName = ""
		self.fileMD5 = ""
		self.rankedStatus = rankedStatuses.NOT_SUBMITTED
		self.rankedStatusFrozen = 0
		self.beatmapID = 0
		self.beatmapSetID = 0
		self.offset = 0		# Won't implement
		self.rating = 0.

		self.starsStd = 0.0	# stars for converted
		self.starsTaiko = 0.0	# stars for converted
		self.starsCtb = 0.0		# stars for converted
		self.starsMania = 0.0	# stars for converted
		self.AR = 0.0
		self.OD = 0.0
		self.maxCombo = 0
		self.hitLength = 0
		self.bpm = 0

		# Statistics for ranking panel
		self.playcount = 0

		# Force refresh from osu api
		self.refresh = refresh

		if md5 is not None and beatmapSetID is not None:
			self.setData(md5, beatmapSetID)
	
	def addBeatmapToDB(self):
		"""
		Add current beatmap data in db if not in yet
		"""

		if self.fileMD5 is None:
			self.rankedStatus = rankedStatuses.NOT_SUBMITTED
			return 

		# Make sure the beatmap is not already in db
		bdata = glob.db.fetch("SELECT ranked_status_freezed, ranked FROM beatmaps WHERE beatmap_md5 LIKE %s LIMIT 1", [self.fileMD5])
		if bdata is not None:
			frozen = bdata["ranked_status_freezed"]
			if frozen > 0:
				self.rankedStatus = bdata["ranked"]
		
			

				glob.db.execute("UPDATE `beatmaps` SET (`id`, `beatmap_id`, `beatmapset_id`, `beatmap_md5`, `song_name`, `ar`, `od`, `difficulty_std`, `difficulty_taiko`, `difficulty_ctb`, `difficulty_mania`, `max_combo`, `hit_length`, `bpm`, `ranked`, `latest_update`, `ranked_status_freezed`) VALUES (NULL, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);", [
					self.beatmapID,
					self.beatmapSetID,
					self.fileMD5,
					self.songName.encode("utf-8", "ignore").decode("utf-8"),
					self.AR,
					self.OD,
					self.starsStd,
					self.starsTaiko,
					self.starsCtb,
					self.starsMania,
					self.maxCombo,
					self.hitLength,
					self.bpm,
					self.rankedStatus,
					int(time.time()),
					frozen
				])
		
		else:
			frozen = 0
			try:
				glob.db.execute("INSERT INTO `beatmaps` (`id`, `beatmap_id`, `beatmapset_id`, `beatmap_md5`, `song_name`, `ar`, `od`, `difficulty_std`, `difficulty_taiko`, `difficulty_ctb`, `difficulty_mania`, `max_combo`, `hit_length`, `bpm`, `ranked`, `latest_update`, `ranked_status_freezed`) VALUES (NULL, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);", [
					self.beatmapID,
					self.beatmapSetID,
					self.fileMD5,
					self.songName.encode("utf-8", "ignore").decode("utf-8"),
					self.AR,
					self.OD,
					self.starsStd,
					self.starsTaiko,
					self.starsCtb,
					self.starsMania,
					self.maxCombo,
					self.hitLength,
					self.bpm,
					self.rankedStatus if frozen == 0 else 2,
					int(time.time()),
					frozen
				])

			except:
				log.error("who the fuck knows ¯\_(ツ)_/¯ {} id".format(self.beatmapID))
				#glob.db.execute("DELETE FROM beatmaps WHERE beatmap_id = %s ",[self.beatmapID])
				#self.rankedStatus = rankedStatuses.NEED_UPDATE
				pass
	def setDataFromDB(self, md5):
		"""
		Set this object's beatmap data from db.
		md5 -- beatmap md5
		return -- True if set, False if not set
		"""
		# Get data from DB
		data = glob.db.fetch("SELECT * FROM beatmaps WHERE beatmap_md5 = %s LIMIT 1", [md5])

		# Make sure the query returned something
		if data is None:
			return False

		# Make sure the beatmap is not an old one
		if data["difficulty_taiko"] == 0 and data["difficulty_ctb"] == 0 and data["difficulty_mania"] == 0:
			log.debug("Difficulty for non-std gamemodes not found in DB, refreshing data from osu!api...")
			return False

		# Set cached data period
		expire = int(glob.conf.config["server"]["beatmapcacheexpire"])

		# If the beatmap is ranked, we don't need to refresh data from osu!api that often
		if data["ranked"] >= rankedStatuses.RANKED and data["ranked_status_freezed"] == 0:
			expire *= 3

		if int(expire) > 0 and time.time() > data["latest_update"]+int(expire):
			if data["ranked_status_freezed"] == 1:
				self.setDataFromDict(data)

		# Data in DB, set beatmap data
		log.debug("Got beatmap data from db")
		self.setDataFromDict(data)
		self.rating = data["rating"]	# db only, we don't want the rating from osu! api.
		return True

	def setDataFromDict(self, data):
		"""
		Set this object's beatmap data from data dictionary.
		data -- data dictionary
		return -- True if set, False if not set
		"""
		self.songName = data["song_name"]
		self.fileMD5 = data["beatmap_md5"]
		self.rankedStatus = int(data["ranked"])
		self.rankedStatusFrozen = int(data["ranked_status_freezed"])
		self.beatmapID = int(data["beatmap_id"])
		self.beatmapSetID = int(data["beatmapset_id"])
		self.AR = float(data["ar"])
		self.OD = float(data["od"])
		self.starsStd = float(data["difficulty_std"])
		self.starsTaiko = float(data["difficulty_taiko"])
		self.starsCtb = float(data["difficulty_ctb"])
		self.starsMania = float(data["difficulty_mania"])
		self.maxCombo = int(data["max_combo"])
		self.hitLength = int(data["hit_length"])
		self.bpm = int(data["bpm"])
		# Ranking panel statistics
		self.playcount = int(data["playcount"]) if "playcount" in data else 0
		self.passcount = int(data["passcount"]) if "passcount" in data else 0
	def beatmapStatus(self, md5):
		status = glob.redis.get("lets:beatmap_status:{}".format(md5))
		if status is not None:
			status = int(status)
			if status < 2:
				self.rankedStatus = status
				return False
			return True
		fileContent = osuapiHelper.getOsuFileFromID(self.beatmapID)
		if fileContent is not None:
			fileMD5 = generalUtils.stringMd5(fileContent.decode())
			status = 2
			result = True
			if fileMD5 != md5:
				self.rankedStatus = rankedStatuses.NEED_UPDATE
				status = 1
				result = False
		else:
			self.rankedStatus = rankedStatuses.NOT_SUBMITTED
			status = -1
			result = False
		glob.redis.set("lets:beatmap_status:{}".format(md5), status, 300)
		return result
	def setDataFromOsuApi(self, md5, beatmapSetID, diffData = None):

		if md5 is None or beatmapSetID is None or beatmapSetID == 0 or md5 == "":
			return None
		"""
		Set this object's beatmap data from osu!api.
		md5 -- beatmap md5
		beatmapSetID -- beatmap set ID, used to check if a map is outdated
		return -- True if set, False if not set
		"""
		# Check if osuapi is enabled
		dbMD5 = glob.db.fetch("SELECT beatmap_md5, ranked FROM beatmaps WHERE beatmap_md5 = %s",[md5])
		if dbMD5 is not None and self.refresh == False:
			return True

		mainData = None
		if diffData == None:
			diffData = osuapiHelper.getDifficulty(md5)
		
		if diffData is not None:
			mainData = osuapiHelper.osuApiRequest("get_beatmaps", "h={}".format(md5))
		if mainData is not None:
			pattern = re.compile("(evilarthas|arthas|papich)")
			match = pattern.search(mainData["tags"])
			match = True if mainData["artist"].lower().startswith('papich') else match
			match = True if mainData["artist"].lower().startswith('madevil') else match
			if match:
				mainData = None
		# Can't fint beatmap by MD5. The beatmap has been updated.
		if mainData is None:
			log.error("Beatmap data from osu api is empty! beatmap_md5 = {}".format(md5))
			self.fileMD5 = None
			return False

		try:
			self.fileMD5 = md5
			self.rankedStatus = convertRankedStatus(int(mainData["approved"]))
			if self.rankedStatus == rankedStatuses.QUALIFIED:
				glob.db.execute("UPDATE beatmaps SET latest_update = latest_update - 219600 WHERE beatmapset_id = %s AND ranked != 4",[beatmapSetID])
			if dbMD5 is not None:
				if dbMD5["ranked"] == 4 and self.rankedStatus != rankedStatuses.QUALIFIED:
					glob.db.execute("UPDATE beatmaps SET ranked = %s WHERE beatmapset_id = %s",[self.rankedStatus, beatmapSetID])
				
		except Exception:
			return False							
		log.debug("Got beatmap data from osu!api")
		self.songName = "{} - {} [{}]".format(mainData["artist"], mainData["title"], mainData["version"])
		self.AR = float(mainData["diff_approach"])
		self.OD = float(mainData["diff_overall"])
		self.HP = float(mainData["diff_drain"])
		self.CS = float(mainData["diff_size"])
		self.mode = int(mainData["mode"])
		self.artist = mainData["artist"]
		self.title = mainData["title"]
		self.rankingDate = int(time.mktime(datetime.datetime.strptime(mainData["last_update"], "%Y-%m-%d %H:%M:%S").timetuple()))
		self.version = mainData["version"]
		self.creator = mainData["creator"]
		self.beatmapID = int(mainData["beatmap_id"])
		self.beatmapSetID = int(mainData["beatmapset_id"])
		# Determine stars for every mode
		self.starsStd = 0
		self.starsTaiko = 0
		self.starsCtb = 0
		self.starsMania = 0
		if self.mode == 0:
			self.starsStd = float(diffData[0]["difficulty"])
			if len(diffData) > 1:
				self.starsTaiko = float(diffData[1]["difficulty"])
			if len(diffData) > 2:
				self.starsCtb = float(diffData[2]["difficulty"])
			if len(diffData) > 3:
				self.starsMania = float(diffData[3]["difficulty"])
		else:
			modeText = getGameModeForDB(self.mode).title()
			setattr(self, 'stars{}'.format(modeText), float(diffData[0]["difficulty"]))

		self.maxCombo = int(mainData["max_combo"]) if mainData["max_combo"] is not None else 0
		self.hitLength = int(mainData["hit_length"])
		if mainData["bpm"] is not None:
			self.bpm = int(float(mainData["bpm"]))
		else:
			self.bpm = -1
		if self.rankedStatus != rankedStatuses.NOT_SUBMITTED and self.rankedStatus != rankedStatuses.NEED_UPDATE and self.rankedStatus != rankedStatuses.UNKNOWN:	
			self.addBeatmapToDB()
		return True
	def setData(self, md5, beatmapSetID):
		"""
		Set this object's beatmap data from highest level possible.
		md5 -- beatmap MD5
		beatmapSetID -- beatmap set ID
		"""
		# Get beatmap from db
		dbResult = self.setDataFromDB(md5)

		# Force refresh from osu api.
		# We get data before to keep frozen maps ranked
		# if they haven't been updated
		if dbResult and self.refresh:
			dbResult = False

		if not dbResult:
			log.debug("Beatmap not found in db")
			# If this beatmap is not in db, get it from osu!api
			apiResult = None
			if self.beatmapStatus(md5) == True:
				apiResult = self.setDataFromOsuApi(md5, beatmapSetID)
			if not apiResult:	
				log.debug("beatmap not found in api")
		else:
			log.debug("Beatmap found in db")

	
	def getData(self, totalScores=0, version=4):
		"""
		Return this beatmap's data (header) for getscores
		return -- beatmap header for getscores
		"""
		rankedStatusOutput = self.rankedStatus


		if self.rankedStatus == rankedStatuses.LOVED:
			rankedStatusOutput = rankedStatuses.APPROVED

		if self.rankedStatus == rankedStatuses.PENDING:
			rankedStatusOutput = rankedStatuses.LOVED		


		# Fix loved maps for old clients
		if version < 4 and self.rankedStatus == rankedStatuses.LOVED:
			rankedStatusOutput = rankedStatuses.QUALIFIED

		data = "{}|false".format(rankedStatusOutput)
		if self.rankedStatus != rankedStatuses.NOT_SUBMITTED and self.rankedStatus != rankedStatuses.NEED_UPDATE and self.rankedStatus != rankedStatuses.UNKNOWN:
			# If the beatmap is updated and exists, the client needs more data
			data += "|{}|{}|{}\n{}\n{}\n{}\n".format(self.beatmapID, self.beatmapSetID, totalScores, self.offset, self.songName, self.rating)

		# Return the header
		return data
	def getCachedTillerinoPP(self):
		"""
		Returned cached pp values for 100, 99, 98 and 95 acc nomod
		(used ONLY with Tillerino, pp is always calculated with oppai when submitting scores)
		return -- list with pp values. [0,0,0,0] if not cached.
		"""
		data = glob.db.fetch("SELECT pp_100, pp_99, pp_98, pp_95 FROM beatmaps WHERE beatmap_md5 = %s LIMIT 1", [self.fileMD5])
		if data is None:
			return [0,0,0,0]
		return [data["pp_100"], data["pp_99"], data["pp_98"], data["pp_95"]]

	def saveCachedTillerinoPP(self, l):
		"""
		Save cached pp for tillerino
		l -- list with 4 default pp values ([100,99,98,95])
		"""
		glob.db.execute("UPDATE beatmaps SET pp_100 = %s, pp_99 = %s, pp_98 = %s, pp_95 = %s WHERE beatmap_md5 = %s", [l[0], l[1], l[2], l[3], self.fileMD5])

	@property
	def is_rankable(self):
		return self.rankedStatus >= rankedStatuses.RANKED and self.rankedStatus != rankedStatuses.UNKNOWN

def convertRankedStatus(approvedStatus):
	"""
	Convert approved_status (from osu!api) to ranked status (for getscores)
	approvedStatus -- approved status, from osu!api
	return -- rankedStatus for getscores
	"""

	approvedStatus = int(approvedStatus)
	if approvedStatus <= 0:
		return rankedStatuses.PENDING
	elif approvedStatus == 1:
		return rankedStatuses.RANKED
	elif approvedStatus == 2:
		return rankedStatuses.APPROVED
	elif approvedStatus == 3:
		return rankedStatuses.QUALIFIED
	elif approvedStatus == 4:
		return rankedStatuses.LOVED
	else:
		return rankedStatuses.UNKNOWN

def incrementPlaycount(md5, passed):
	"""
	Increment playcount (and passcount) for a beatmap
	md5 -- beatmap md5
	passed -- if True, increment passcount too
	"""
	glob.db.execute("UPDATE beatmaps SET playcount = playcount+1 WHERE beatmap_md5 = %s LIMIT 1", [md5])
	if passed:
		glob.db.execute("UPDATE beatmaps SET passcount = passcount+1 WHERE beatmap_md5 = %s LIMIT 1", [md5])
